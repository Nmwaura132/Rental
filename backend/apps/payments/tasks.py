import logging
from datetime import timedelta
from decimal import Decimal, InvalidOperation
from celery import shared_task
from django.db import transaction as db_transaction
from django.utils import timezone

from .models import Invoice, Payment, BankPaymentNotification
from .mpesa import make_idempotency_key

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def process_mpesa_payment(self, receipt_number, amount, account_ref, phone, idempotency_key):
    """
    Match an M-Pesa C2B payment to an open invoice and record it.
    account_ref is the BillRefNumber the tenant entered (typically unit number).
    `amount` is a string (JSON-safe); parsed to Decimal here.
    """
    from apps.tenants.models import Lease
    from .models import Invoice, Payment
    from apps.core.utils.phone import normalize_phone

    try:
        # WHY: parse to Decimal at the boundary. Daraja sends "TransAmount" as a
        # JSON string or number; either way, str()->Decimal preserves cents.
        try:
            amount_dec = Decimal(str(amount))
        except (TypeError, ValueError, InvalidOperation):
            logger.error("Invalid amount in M-Pesa payload: %r (receipt=%s)", amount, receipt_number)
            return

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

        # WHY: wrap the Payment.create + Invoice update in a single transaction and
        # take a row lock on the Invoice. Two concurrent C2B callbacks for the same
        # invoice (Safaricom retries) would otherwise race the read-modify-write on
        # amount_paid and corrupt the balance. The idempotency_key prevents a
        # double Payment row; the lock prevents the lost-update on amount_paid.
        with db_transaction.atomic():
            # Find oldest unpaid invoice for this lease — locked for update.
            invoice = (
                Invoice.objects
                .select_for_update()
                .filter(lease=lease, status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE, Invoice.Status.PARTIALLY_PAID])
                .order_by("due_date")
                .first()
            )

            if not invoice:
                logger.warning("No open invoice for lease=%s receipt=%s", lease.id, receipt_number)
                return

            # Idempotency belt-and-suspenders: skip if this receipt already recorded.
            if Payment.objects.filter(idempotency_key=idempotency_key).exists():
                logger.info("Idempotent skip for receipt=%s", receipt_number)
                return

            payment = Payment.objects.create(
                invoice=invoice,
                method=Payment.Method.MPESA,
                status=Payment.Status.CONFIRMED,
                amount=amount_dec,
                mpesa_receipt_number=receipt_number,
                mpesa_phone=normalized_phone,
                mpesa_account_ref=account_ref,
                idempotency_key=idempotency_key,
                paid_at=timezone.now(),
            )

            invoice.amount_paid = (invoice.amount_paid or Decimal("0")) + payment.amount
            invoice.status = (
                Invoice.Status.PAID if invoice.amount_paid >= invoice.amount_due
                else Invoice.Status.PARTIALLY_PAID
            )
            invoice.save(update_fields=["amount_paid", "status"])

        # Send SMS receipt (after commit — task can be retried if the row isn't visible yet)
        from apps.notifications.tasks import send_payment_receipt_sms
        send_payment_receipt_sms.delay(payment.id)

        # Invalidate dashboard cache for tenant and landlord
        from django.core.cache import cache
        cache.delete(f"dashboard:{lease.tenant.id}")
        cache.delete(f"dashboard:{lease.unit.property.owner.id}")

        logger.info("Payment recorded: receipt=%s amount=%s invoice=%s", receipt_number, amount_dec, invoice.invoice_number)

    except Exception as exc:
        logger.error("Error processing M-Pesa payment %s: %s", receipt_number, exc)
        raise self.retry(exc=exc)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_stk_callback(self, payload: dict):
    """
    Process an STK Push callback from Safaricom.
    Locks both the MpesaSTKRequest row AND the linked Invoice row so concurrent
    callbacks/reconciles can't race the amount_paid update.
    """
    from .models import MpesaSTKRequest, Payment

    stk = payload.get("Body", {}).get("stkCallback", {})
    checkout_id = stk.get("CheckoutRequestID", "")
    result_code = stk.get("ResultCode")

    if not checkout_id:
        logger.error("STK callback missing CheckoutRequestID: %s", payload)
        return

    payment_id_for_sms = None
    cache_keys_to_invalidate = []

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
                if req.invoice_id:
                    idempotency_key = make_idempotency_key(receipt)
                    if not Payment.objects.filter(idempotency_key=idempotency_key).exists():
                        # WHY: re-fetch the invoice with select_for_update so two
                        # callbacks for the SAME invoice (partial-pay scenarios with
                        # different STK requests) serialize their amount_paid updates.
                        # Without this, the STK row lock only protects this row;
                        # the Invoice read-modify-write could still race.
                        invoice = (
                            Invoice.objects
                            .select_for_update()
                            .select_related("lease__tenant", "lease__unit__property__owner")
                            .get(pk=req.invoice_id)
                        )
                        try:
                            amount_dec = Decimal(str(paid_amount if paid_amount is not None else req.amount))
                        except (TypeError, ValueError, InvalidOperation):
                            logger.error("Invalid STK amount %r for receipt=%s", paid_amount, receipt)
                            return

                        payment = Payment.objects.create(
                            invoice=invoice,
                            method=Payment.Method.MPESA,
                            status=Payment.Status.CONFIRMED,
                            amount=amount_dec,
                            mpesa_receipt_number=receipt,
                            mpesa_phone=phone,
                            mpesa_account_ref=req.account_ref,
                            idempotency_key=idempotency_key,
                            paid_at=timezone.now(),
                        )
                        invoice.amount_paid = (invoice.amount_paid or Decimal("0")) + payment.amount
                        invoice.status = (
                            Invoice.Status.PAID if invoice.amount_paid >= invoice.amount_due
                            else Invoice.Status.PARTIALLY_PAID
                        )
                        invoice.save(update_fields=["amount_paid", "status"])

                        payment_id_for_sms = payment.id
                        cache_keys_to_invalidate = [
                            f"dashboard:{invoice.lease.tenant_id}",
                            f"dashboard:{invoice.lease.unit.property.owner_id}",
                        ]
            else:
                # User cancelled (1032), timeout (1037), insufficient funds (1), etc.
                req.status = MpesaSTKRequest.Status.CANCELLED if result_code == 1032 \
                    else MpesaSTKRequest.Status.FAILED
                req.save()

        # WHY: side effects (SMS dispatch, cache invalidation) happen AFTER commit.
        # Otherwise the SMS task could see an uncommitted Payment row and crash.
        if payment_id_for_sms:
            from apps.notifications.tasks import send_payment_receipt_sms
            send_payment_receipt_sms.delay(payment_id_for_sms)
        if cache_keys_to_invalidate:
            from django.core.cache import cache
            for key in cache_keys_to_invalidate:
                cache.delete(key)

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


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_bank_notification(self, notification_id: int):
    """
    Reconcile a BankPaymentNotification against open invoices.
    Called immediately after KCB or Equity IPN is received.
    """
    from .models import BankPaymentNotification
    from .bank_reconcile import reconcile_bank_notification
    try:
        notification = BankPaymentNotification.objects.get(pk=notification_id)
        reconcile_bank_notification(notification)
    except BankPaymentNotification.DoesNotExist:
        logger.error("BankPaymentNotification %s not found.", notification_id)
    except Exception as exc:
        logger.error("Error reconciling bank notification %s: %s", notification_id, exc)
        raise self.retry(exc=exc)


@shared_task
def poll_equity_statement(date_from: str | None = None, date_to: str | None = None):
    """
    Pull recent Equity transactions via Jenga API and reconcile any new ones.
    Celery Beat: run every 30 minutes (catches EFTs with no IPN).
    Can also be triggered manually via POST /api/v1/payments/bank/equity/poll/.
    """
    from datetime import date, timedelta
    from .models import BankPaymentNotification
    from .bank_reconcile import reconcile_bank_notification
    try:
        from .jenga import get_mini_statement, get_full_statement
    except Exception as exc:
        logger.error("Jenga import error: %s", exc)
        return

    try:
        if date_from and date_to:
            transactions = get_full_statement(date_from, date_to)
        else:
            transactions = get_mini_statement()
    except Exception as exc:
        logger.error("Equity statement fetch failed: %s", exc)
        return

    new_count = 0
    for txn in transactions:
        # Normalize Jenga transaction shape
        # Jenga full-statement fields: transactionReference, amount, date, narrative, debitCredit
        ref = (
            txn.get("transactionReference")
            or txn.get("reference")
            or txn.get("TransID", "")
        ).strip()
        if not ref:
            continue

        debit_credit = txn.get("debitCredit", txn.get("type", "")).upper()
        if debit_credit and debit_credit not in ("C", "CREDIT", "CR"):
            continue  # skip debits

        if BankPaymentNotification.objects.filter(transaction_ref=ref).exists():
            continue  # already processed

        try:
            from decimal import Decimal
            amount = Decimal(str(txn.get("amount", txn.get("runningBalance", 0))))
            date_str = txn.get("date", txn.get("transactionDate", ""))
            from datetime import timezone
            from django.utils import timezone as dj_timezone
            credited_at = (
                __import__("dateutil.parser", fromlist=["parse"]).parse(date_str).replace(tzinfo=timezone.utc)
                if date_str else dj_timezone.now()
            )
        except Exception as exc:
            logger.warning("Equity statement parse error for txn %s: %s", ref, exc)
            continue

        narrative = txn.get("narrative", txn.get("remarks", ""))
        notification = BankPaymentNotification.objects.create(
            bank=BankPaymentNotification.Bank.EQUITY,
            transaction_ref=ref,
            amount=amount,
            payer_name=txn.get("payerName", ""),
            payer_account=txn.get("payerAccount", ""),
            payment_ref=narrative[:100],
            credited_at=credited_at,
            raw_payload=txn,
        )
        reconcile_bank_notification(notification)
        new_count += 1

    logger.info("Equity statement poll: %d new transactions processed.", new_count)
    return new_count


@shared_task
def generate_monthly_invoices():
    """
    Celery Beat task — runs on the 1st of each month.
    Creates invoices for all active leases.

    WHY due_date = period_start + 7 days: invoices are generated on the 1st,
    and `send_rent_reminders` fires reminders at -7d, -3d, 0d before due_date.
    With due_date == period_start, the -7d and -3d reminders looked for invoices
    that didn't exist yet. Pushing due to the 8th gives tenants a real grace
    window AND aligns the reminder cadence with reality (reminder #1 lands the
    same day the invoice arrives).
    """
    from apps.tenants.models import Lease
    from .models import Invoice
    from django.utils import timezone
    import uuid

    today = timezone.now().date()
    period_start = today.replace(day=1)
    next_month = (today.replace(day=28) + timedelta(days=4)).replace(day=1)
    period_end = next_month - timedelta(days=1)
    due_date = period_start + timedelta(days=7)  # 8th of the month — gives reminder window room

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
