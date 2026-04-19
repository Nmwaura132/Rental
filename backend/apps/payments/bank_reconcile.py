"""
Shared reconciliation logic for bank IPN / statement-poll payments.

Match priority:
  1. Exact invoice number in payment_ref
  2. Unit number in payment_ref → oldest open invoice for that unit's active lease
  3. Single amount match (±50 KES) across all active leases
  4. No match → leave UNMATCHED for landlord manual review
"""
import logging
from decimal import Decimal
from django.db import transaction as db_transaction

logger = logging.getLogger(__name__)

_AMOUNT_TOLERANCE = Decimal("50.00")


def reconcile_bank_notification(notification) -> bool:
    """
    Attempt to match *notification* to an open invoice and create a Payment.
    Returns True if matched, False if left unmatched.
    """
    from .models import Invoice, Payment, BankPaymentNotification
    from apps.tenants.models import Lease

    if notification.status == BankPaymentNotification.Status.MATCHED:
        return True

    ref = (notification.payment_ref or "").strip().upper()
    amount = notification.amount
    invoice = None

    # ── 1. Exact invoice number ────────────────────────────────────────────────
    if ref:
        invoice = (
            Invoice.objects
            .filter(
                invoice_number__iexact=ref,
                status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE, Invoice.Status.PARTIALLY_PAID],
            )
            .first()
        )

    # ── 2. Unit number → oldest open invoice ──────────────────────────────────
    if not invoice and ref:
        lease = (
            Lease.objects
            .filter(unit__unit_number__iexact=ref, status=Lease.Status.ACTIVE)
            .select_related("unit")
            .first()
        )
        if lease:
            invoice = (
                Invoice.objects
                .filter(
                    lease=lease,
                    status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE, Invoice.Status.PARTIALLY_PAID],
                )
                .order_by("due_date")
                .first()
            )

    # ── 3. Fuzzy amount match (only if result is unambiguous) ─────────────────
    if not invoice:
        candidates = Invoice.objects.filter(
            status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE, Invoice.Status.PARTIALLY_PAID],
            amount_due__gte=amount - _AMOUNT_TOLERANCE,
            amount_due__lte=amount + _AMOUNT_TOLERANCE,
            lease__status=Lease.Status.ACTIVE,
        ).order_by("due_date")
        if candidates.count() == 1:
            invoice = candidates.first()

    if not invoice:
        logger.info(
            "BankNotification %s (%s): no matching invoice found — left UNMATCHED.",
            notification.transaction_ref,
            notification.bank,
        )
        return False

    idempotency_key = f"bank:{notification.bank}:{notification.transaction_ref}"

    with db_transaction.atomic():
        if Payment.objects.filter(idempotency_key=idempotency_key).exists():
            notification.status = BankPaymentNotification.Status.DUPLICATE
            notification.save(update_fields=["status"])
            logger.warning("Duplicate bank notification ignored: %s", notification.transaction_ref)
            return False

        payment = Payment.objects.create(
            invoice=invoice,
            method=Payment.Method.BANK,
            status=Payment.Status.CONFIRMED,
            amount=amount,
            idempotency_key=idempotency_key,
            paid_at=notification.credited_at,
            bank_name=notification.get_bank_display(),
            bank_account=notification.payer_account or None,
            bank_reference=notification.transaction_ref,
        )

        invoice.amount_paid = (invoice.amount_paid or Decimal("0")) + amount
        invoice.status = (
            Invoice.Status.PAID
            if invoice.amount_paid >= invoice.amount_due
            else Invoice.Status.PARTIALLY_PAID
        )
        invoice.save(update_fields=["amount_paid", "status"])

        notification.status = BankPaymentNotification.Status.MATCHED
        notification.payment = payment
        notification.save(update_fields=["status", "payment"])

    # Invalidate dashboard caches
    from django.core.cache import cache
    tenant = invoice.lease.tenant
    landlord = invoice.lease.unit.property.owner
    cache.delete(f"dashboard:{tenant.id}")
    cache.delete(f"dashboard:{landlord.id}")

    from apps.notifications.tasks import send_payment_receipt_sms
    send_payment_receipt_sms.delay(payment.id)

    logger.info(
        "BankNotification %s matched → invoice %s (KES %s)",
        notification.transaction_ref,
        invoice.invoice_number,
        amount,
    )
    return True
