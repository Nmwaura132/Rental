import logging
from datetime import timedelta
from celery import shared_task
from django.utils import timezone

from .models import Invoice, Payment
from .mpesa import make_idempotency_key

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def process_mpesa_payment(self, receipt_number, amount, account_ref, phone, idempotency_key):
    """
    Match an M-Pesa C2B payment to an open invoice and record it.
    account_ref is the BillRefNumber the tenant entered (typically unit number).
    """
    from apps.tenants.models import Lease
    from .models import Invoice, Payment
    from apps.core.utils.phone import normalize_phone

    try:
        # Normalize incoming phone
        normalized_phone = normalize_phone(phone)

        # Find the active lease by unit number (account_ref)
        lease = (
            Lease.objects
            .filter(unit__unit_number__iexact=account_ref, status=Lease.Status.ACTIVE)
            .select_related("unit__property", "tenant")
            .first()
        )

        if not lease:
            logger.warning("No active lease found for account_ref=%s receipt=%s", account_ref, receipt_number)
            return

        # Find the oldest unpaid invoice for this lease
        invoice = (
            Invoice.objects
            .filter(lease=lease, status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE, Invoice.Status.PARTIALLY_PAID])
            .order_by("due_date")
            .first()
        )

        if not invoice:
            logger.warning("No open invoice for lease=%s receipt=%s", lease.id, receipt_number)
            return

        # Record the payment
        payment = Payment.objects.create(
            invoice=invoice,
            method=Payment.Method.MPESA,
            status=Payment.Status.CONFIRMED,
            amount=amount,
            mpesa_receipt_number=receipt_number,
            mpesa_phone=normalized_phone,
            mpesa_account_ref=account_ref,
            idempotency_key=idempotency_key,
            paid_at=timezone.now(),
        )

        # Update invoice totals
        invoice.amount_paid += payment.amount
        if invoice.amount_paid >= invoice.amount_due:
            invoice.status = Invoice.Status.PAID
        else:
            invoice.status = Invoice.Status.PARTIALLY_PAID
        invoice.save(update_fields=["amount_paid", "status"])

        # Send SMS receipt
        from apps.notifications.tasks import send_payment_receipt_sms
        send_payment_receipt_sms.delay(payment.id)

        # Invalidate dashboard cache for tenant and landlord
        from django.core.cache import cache
        cache.delete(f"dashboard:{lease.tenant.id}")
        cache.delete(f"dashboard:{lease.unit.property.owner.id}")

        logger.info("Payment recorded: receipt=%s amount=%s invoice=%s", receipt_number, amount, invoice.invoice_number)

    except Exception as exc:
        logger.error("Error processing M-Pesa payment %s: %s", receipt_number, exc)
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_stk_callback(self, payload: dict):
    """
    Process an STK Push callback from Safaricom.
    Uses select_for_update to prevent race conditions on duplicate callbacks.
    """
    from django.db import transaction as db_transaction
    from .models import MpesaSTKRequest, Payment

    stk = payload.get("Body", {}).get("stkCallback", {})
    checkout_id = stk.get("CheckoutRequestID", "")
    result_code = stk.get("ResultCode")

    if not checkout_id:
        logger.error("STK callback missing CheckoutRequestID: %s", payload)
        return

    try:
        with db_transaction.atomic():
            try:
                req = MpesaSTKRequest.objects.select_for_update().get(
                    checkout_request_id=checkout_id
                )
            except MpesaSTKRequest.DoesNotExist:
                logger.warning("STK callback for unknown CheckoutRequestID: %s", checkout_id)
                return

            if req.status != MpesaSTKRequest.Status.PENDING:
                logger.info("STK callback already processed for %s, skipping.", checkout_id)
                return

            req.result_code = result_code
            req.result_desc = stk.get("ResultDesc", "")
            req.raw_callback = payload

            if result_code == 0:
                items = {
                    i["Name"]: i["Value"]
                    for i in stk.get("CallbackMetadata", {}).get("Item", [])
                }
                receipt = str(items.get("MpesaReceiptNumber", ""))
                paid_amount = items.get("Amount")
                phone = str(items.get("PhoneNumber", req.phone))

                # Deduplicate by receipt number
                if MpesaSTKRequest.objects.filter(mpesa_receipt_number=receipt).exists():
                    logger.warning("Duplicate STK receipt %s — skipping.", receipt)
                    return

                req.status = MpesaSTKRequest.Status.SUCCESS
                req.mpesa_receipt_number = receipt
                req.save()

                # Record payment on linked invoice
                if req.invoice:
                    idempotency_key = make_idempotency_key(receipt)
                    if not Payment.objects.filter(idempotency_key=idempotency_key).exists():
                        from decimal import Decimal
                        payment = Payment.objects.create(
                            invoice=req.invoice,
                            method=Payment.Method.MPESA,
                            status=Payment.Status.CONFIRMED,
                            amount=Decimal(str(paid_amount or req.amount)),
                            mpesa_receipt_number=receipt,
                            mpesa_phone=phone,
                            mpesa_account_ref=req.account_ref,
                            idempotency_key=idempotency_key,
                            paid_at=timezone.now(),
                        )
                        invoice = req.invoice
                        invoice.amount_paid += payment.amount
                        invoice.status = (
                            Invoice.Status.PAID if invoice.amount_paid >= invoice.amount_due
                            else Invoice.Status.PARTIALLY_PAID
                        )
                        invoice.save(update_fields=["amount_paid", "status"])

                        from apps.notifications.tasks import send_payment_receipt_sms
                        send_payment_receipt_sms.delay(payment.id)
                        # Invalidate dashboard cache for tenant and landlord
                        from django.core.cache import cache
                        tenant = req.invoice.lease.tenant
                        landlord = req.invoice.lease.unit.property.owner
                        cache.delete(f"dashboard:{tenant.id}")
                        cache.delete(f"dashboard:{landlord.id}")
            else:
                # User cancelled (1032), timeout (1037), insufficient funds (1), etc.
                req.status = MpesaSTKRequest.Status.CANCELLED if result_code == 1032 \
                    else MpesaSTKRequest.Status.FAILED
                req.save()

    except Exception as exc:
        logger.error("Error processing STK callback for %s: %s", checkout_id, exc)
        raise self.retry(exc=exc)


@shared_task
def reconcile_pending_stk_transactions():
    """
    Celery Beat task — runs every 5 minutes.
    Queries Safaricom for any STK requests still pending after 5 minutes.
    Covers edge case where the callback was never delivered.
    """
    from .models import MpesaSTKRequest
    from .mpesa import stk_query
    import datetime

    cutoff = timezone.now() - datetime.timedelta(minutes=5)
    pending = MpesaSTKRequest.objects.filter(
        status=MpesaSTKRequest.Status.PENDING,
        created_at__lt=cutoff,
    )

    for req in pending:
        try:
            result = stk_query(req.checkout_request_id)
            result_code = result.get("ResultCode")
            if result_code is not None and str(result_code) != "":
                # Build a synthetic callback payload and process it
                synthetic = {
                    "Body": {
                        "stkCallback": {
                            "MerchantRequestID": req.merchant_request_id,
                            "CheckoutRequestID": req.checkout_request_id,
                            "ResultCode": int(result_code),
                            "ResultDesc": result.get("ResultDesc", "Reconciled via query"),
                        }
                    }
                }
                process_stk_callback.delay(synthetic)
        except Exception as e:
            logger.error("STK reconcile query failed for %s: %s", req.checkout_request_id, e)


@shared_task
def generate_monthly_invoices():
    """
    Celery Beat task — runs on the 1st of each month.
    Creates invoices for all active leases.
    """
    from apps.tenants.models import Lease
    from .models import Invoice
    from django.utils import timezone
    import uuid

    today = timezone.now().date()
    period_start = today.replace(day=1)
    next_month = (today.replace(day=28) + timedelta(days=4)).replace(day=1)
    period_end = next_month - timedelta(days=1)
    due_date = period_start  # due on 1st

    active_leases = Lease.objects.filter(status=Lease.Status.ACTIVE).select_related("unit", "tenant")
    created = 0

    for lease in active_leases:
        # Skip if already invoiced this period
        if Invoice.objects.filter(lease=lease, period_start=period_start).exists():
            continue
        Invoice.objects.create(
            lease=lease,
            invoice_number=f"INV-{period_start.strftime('%Y%m')}-{uuid.uuid4().hex[:6].upper()}",
            amount_due=lease.rent_amount,
            due_date=due_date,
            period_start=period_start,
            period_end=period_end,
        )
        created += 1

    logger.info("Generated %d invoices for period %s", created, period_start)
    return created
