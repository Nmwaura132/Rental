from datetime import timedelta
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from .models import Invoice, Payment


def invoice_status_for(invoice: Invoice) -> str:
    if invoice.amount_paid >= invoice.amount_due:
        return Invoice.Status.PAID
    if invoice.due_date < timezone.localdate():
        return Invoice.Status.OVERDUE
    if invoice.amount_paid > Decimal("0"):
        return Invoice.Status.PARTIALLY_PAID
    return Invoice.Status.PENDING


@transaction.atomic
def apply_confirmed_payment(
    *,
    invoice_id: int,
    method: str,
    amount: Decimal,
    idempotency_key: str,
    paid_at,
    payment_fields: dict | None = None,
    recorded_by=None,
) -> tuple[Payment, bool]:
    amount = Decimal(str(amount))
    if amount <= 0:
        raise ValidationError("Payment amount must be greater than zero.")

    invoice = Invoice.objects.select_for_update().get(pk=invoice_id)
    existing = Payment.objects.filter(idempotency_key=idempotency_key).first()
    if existing:
        if existing.invoice_id != invoice_id:
            raise ValidationError("Idempotency key is already assigned to another invoice.")
        return existing, False
    if invoice.status in [Invoice.Status.PAID, Invoice.Status.CANCELLED]:
        raise ValidationError("Closed invoices cannot receive payments.")

    payment = Payment.objects.create(
        invoice=invoice,
        method=method,
        status=Payment.Status.CONFIRMED,
        amount=amount,
        idempotency_key=idempotency_key,
        paid_at=paid_at,
        recorded_by=recorded_by,
        **(payment_fields or {}),
    )
    invoice.amount_paid = (invoice.amount_paid or Decimal("0")) + amount
    invoice.status = invoice_status_for(invoice)
    invoice.save(update_fields=["amount_paid", "status", "updated_at"])
    return payment, True


def create_move_in_invoice(tenancy, *, notify=True):
    """Raise the tenant's first invoice: the first month's rent, plus the
    deposit if it has not already been handed over.

    WHY one invoice with line items rather than two invoices: the tenant pays
    once to move in, and the invoice table is unique on (tenancy, period_start),
    so a second invoice for the same month could not exist anyway. Splitting the
    figures into line items keeps the deposit visible and auditable without
    pretending it is a separate debt.

    Idempotent: called again for the same tenancy and month it returns the
    invoice already there rather than raising a second one.
    """
    from django.utils import timezone
    import uuid

    from .models import Invoice, InvoiceLineItem

    start = tenancy.start_date or timezone.localdate()
    period_start = start.replace(day=1)
    next_month = (period_start + timedelta(days=32)).replace(day=1)
    period_end = next_month - timedelta(days=1)

    # The landlord's agreement has rent payable in advance and the deposit paid
    # before entering, so the first invoice is due on the day they move in —
    # never backdated into being instantly overdue.
    due_date = max(start, timezone.localdate())

    rent = Decimal(tenancy.rent_amount)
    deposit = Decimal("0") if tenancy.deposit_paid else Decimal(tenancy.deposit_amount or 0)

    with transaction.atomic():
        invoice, created = Invoice.objects.get_or_create(
            tenancy=tenancy,
            period_start=period_start,
            defaults={
                "invoice_number": f"INV-{period_start.strftime('%Y%m')}-{uuid.uuid4().hex[:6].upper()}",
                "amount_due": rent + deposit,
                "due_date": due_date,
                "period_end": period_end,
            },
        )
        if not created:
            return invoice, False

        InvoiceLineItem.objects.create(
            invoice=invoice,
            description=f"Rent — {period_start.strftime('%B %Y')}",
            charge_type="rent",
            amount=rent,
        )
        if deposit > 0:
            InvoiceLineItem.objects.create(
                invoice=invoice,
                description="Security deposit",
                charge_type="deposit",
                amount=deposit,
            )

    if notify:
        _notify_move_in(tenancy, invoice, rent, deposit)

    return invoice, True


def _notify_move_in(tenancy, invoice, rent, deposit):
    """Tell the tenant what they owe to move in, and how to pay it."""
    from django.conf import settings

    from apps.notifications.tasks import send_sms

    unit = tenancy.unit
    parts = [f"rent KES {rent:,.0f}"]
    if deposit > 0:
        parts.append(f"deposit KES {deposit:,.0f}")

    send_sms.delay(
        tenancy.tenant_id,
        f"Welcome to {unit.property.name} Unit {unit.unit_number}. "
        f"Your first invoice is {' + '.join(parts)} = "
        f"KES {invoice.amount_due:,.0f}, due {invoice.due_date.strftime('%d %b %Y')}. "
        f"Pay via M-Pesa Paybill {settings.MPESA_SHORTCODE}, Acc: {unit.payment_code}.",
    )
