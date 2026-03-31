import logging
from celery import shared_task
from django.utils import timezone

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def process_mpesa_payment(self, receipt_number, amount, account_ref, phone, idempotency_key):
    """
    Match an M-Pesa C2B payment to an open invoice and record it.
    account_ref is the BillRefNumber the tenant entered (typically unit number).
    """
    from apps.tenants.models import Lease
    from .models import Invoice, Payment

    try:
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
            mpesa_phone=phone,
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
        invoice.save(update_fields=["amount_paid", "status", "updated_at"])

        # Send SMS receipt
        from apps.notifications.tasks import send_payment_receipt_sms
        send_payment_receipt_sms.delay(payment.id)

        logger.info("Payment recorded: receipt=%s amount=%s invoice=%s", receipt_number, amount, invoice.invoice_number)

    except Exception as exc:
        logger.error("Error processing M-Pesa payment %s: %s", receipt_number, exc)
        raise self.retry(exc=exc)


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
    next_month = (today.replace(day=28) + timezone.timedelta(days=4)).replace(day=1)
    period_end = next_month - timezone.timedelta(days=1)
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
