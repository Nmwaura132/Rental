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
        **(payment_fields or {}),
    )
    invoice.amount_paid = (invoice.amount_paid or Decimal("0")) + amount
    invoice.status = invoice_status_for(invoice)
    invoice.save(update_fields=["amount_paid", "status", "updated_at"])
    return payment, True
