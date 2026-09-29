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

    # WHY: deposit_paid was only ever set by hand when the tenancy was created,
    # so a deposit billed on the move-in invoice and then paid still read as
    # unpaid — and the deposit could not be settled when the tenant left. Rent
    # is settled first, so the deposit is only fully held once the bill is.
    if invoice.status == Invoice.Status.PAID and invoice.line_items.filter(charge_type="deposit").exists():
        from apps.tenants.models import Tenancy

        Tenancy.objects.filter(pk=invoice.tenancy_id, deposit_paid=False).update(deposit_paid=True)
    return payment, True


def pay_to(unit) -> tuple[str, str]:
    """The paybill and account number a tenant pays this unit's rent to.

    Behind a bank's shared paybill the account number already identifies the
    landlord ("623943#G1"), so the house number only has to be unique within
    their own buildings and is quoted exactly as the landlord set it. On a
    paybill shared by every landlord, the system-wide payment code is needed
    to tell two landlords' G1s apart.
    """
    from django.conf import settings

    if settings.RENT_ACCOUNT_PREFIX:
        return settings.RENT_PAYBILL, f"{settings.RENT_ACCOUNT_PREFIX}{unit.unit_number}"
    return settings.RENT_PAYBILL, unit.payment_code


def how_to_pay(unit) -> str:
    paybill, account = pay_to(unit)
    return f"Pay via M-Pesa Paybill {paybill}, Acc: {account}."


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
        apply_credit(tenancy)
        invoice.refresh_from_db()

    if notify:
        _notify_move_in(tenancy, invoice, rent, deposit)

    return invoice, True


def _notify_move_in(tenancy, invoice, rent, deposit):
    """Tell the tenant what they owe to move in, and how to pay it."""
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
        f"{how_to_pay(unit)}",
    )


_OPEN_STATUSES = [Invoice.Status.PENDING, Invoice.Status.PARTIALLY_PAID, Invoice.Status.OVERDUE]
_RECEIPT_FIELDS = ("mpesa_receipt_number",)


def _without_receipt(fields: dict) -> dict:
    """The fields for a later part of a payment. The receipt number is unique,
    so only the first part carries it; the rest point back to that part."""
    return {k: v for k, v in (fields or {}).items() if k not in _RECEIPT_FIELDS}


@transaction.atomic
def allocate_payment(
    *,
    tenancy,
    amount,
    method: str,
    idempotency_key: str,
    paid_at,
    payment_fields: dict | None = None,
    recorded_by=None,
    first_invoice_id: int | None = None,
):
    """Place money that arrived for a tenancy.

    Clears open bills oldest first — or the one named, then the rest — and
    keeps anything left over as credit for the next bill.

    WHY: the whole payment used to land on the oldest open bill. A tenant two
    months behind who cleared both at once saw the old bill marked overpaid and
    this month's still chased; anyone who paid ahead was chased the same way.

    Returns (payments, credit_or_None, created). A repeated idempotency key
    returns what was recorded the first time, with created False.
    """
    from .models import TenancyCredit

    amount = Decimal(str(amount))
    if amount <= 0:
        raise ValidationError("Payment amount must be greater than zero.")

    first = Payment.objects.filter(idempotency_key=idempotency_key).first()
    prior_credit = TenancyCredit.objects.filter(idempotency_key=idempotency_key).first()
    if first or prior_credit:
        parts = [first, *first.carried_parts.all()] if first else []
        return parts, prior_credit, False

    bills = list(
        Invoice.objects.select_for_update()
        .filter(tenancy=tenancy, status__in=_OPEN_STATUSES)
        .order_by("due_date", "id")
    )
    if first_invoice_id is not None:
        bills.sort(key=lambda b: b.pk != first_invoice_id)

    remaining = amount
    parts = []
    for bill in bills:
        if remaining <= 0:
            break
        take = min(remaining, bill.balance)
        if take <= 0:
            continue
        if not parts:
            payment, _ = apply_confirmed_payment(
                invoice_id=bill.pk, method=method, amount=take,
                idempotency_key=idempotency_key, paid_at=paid_at,
                payment_fields=payment_fields, recorded_by=recorded_by,
            )
        else:
            payment, _ = apply_confirmed_payment(
                invoice_id=bill.pk, method=method, amount=take,
                idempotency_key=f"{idempotency_key}:{bill.pk}", paid_at=paid_at,
                payment_fields={**_without_receipt(payment_fields), "carried_from": parts[0]},
                recorded_by=recorded_by,
            )
        parts.append(payment)
        remaining -= take

    credit = None
    if remaining > 0:
        credit = TenancyCredit.objects.create(
            tenancy=tenancy,
            idempotency_key=idempotency_key,
            amount=remaining,
            remaining=remaining,
            method=method,
            paid_at=paid_at,
            source_fields=payment_fields or {},
            first_payment=parts[0] if parts else None,
        )
    return parts, credit, True


@transaction.atomic
def apply_credit(tenancy) -> list:
    """Use a tenancy's credit against its open bills, oldest first.

    Called whenever a bill is raised. Each use becomes a Payment dated when the
    money arrived, so it counts in the month it was received.
    """
    from .models import TenancyCredit

    credits = list(
        TenancyCredit.objects.select_for_update()
        .filter(tenancy=tenancy, remaining__gt=0)
        .order_by("created_at", "id")
    )
    if not credits:
        return []
    bills = list(
        Invoice.objects.select_for_update()
        .filter(tenancy=tenancy, status__in=_OPEN_STATUSES)
        .order_by("due_date", "id")
    )

    applied = []
    for credit in credits:
        for bill in bills:
            if credit.remaining <= 0:
                break
            bill.refresh_from_db()
            take = min(credit.remaining, bill.balance)
            if take <= 0:
                continue
            if credit.first_payment is None:
                # The whole payment arrived before any bill: this part carries
                # the receipt, and later parts point back to it.
                payment, _ = apply_confirmed_payment(
                    invoice_id=bill.pk, method=credit.method, amount=take,
                    idempotency_key=credit.idempotency_key, paid_at=credit.paid_at,
                    payment_fields=credit.source_fields,
                )
                credit.first_payment = payment
            else:
                payment, _ = apply_confirmed_payment(
                    invoice_id=bill.pk, method=credit.method, amount=take,
                    idempotency_key=f"credit:{credit.pk}:{bill.pk}", paid_at=credit.paid_at,
                    payment_fields={
                        **_without_receipt(credit.source_fields),
                        "carried_from": credit.first_payment,
                    },
                )
            credit.remaining -= take
            applied.append(payment)
        credit.save(update_fields=["remaining", "first_payment"])
    return applied


def credit_remaining(tenancy) -> Decimal:
    from django.db.models import Sum

    from .models import TenancyCredit

    return TenancyCredit.objects.filter(tenancy=tenancy).aggregate(s=Sum("remaining"))["s"] or Decimal("0")
