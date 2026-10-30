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


def mobile_account(owner):
    """The landlord's own paybill or till, best first, or None."""
    from .models import PaymentAccount

    accounts = list(PaymentAccount.objects.filter(owner=owner, kind__in=PaymentAccount.MOBILE_KINDS))
    for kind in PaymentAccount.MOBILE_KINDS:
        for account in accounts:
            if account.kind == kind:
                return account
    return None


def pay_to(unit) -> tuple[str, str]:
    """The paybill (or till) and account number a tenant pays this unit's rent
    to. A till has no account number, so it comes back empty.

    The landlord's own paybill comes first. Without one, the platform's: behind
    a bank's shared paybill the account number already identifies the landlord
    ("623943#G1"), so the house number is quoted exactly as the landlord set it;
    on a paybill shared by every landlord, the system-wide payment code is
    needed to tell two landlords' G1s apart.
    """
    from django.conf import settings

    from .models import PaymentAccount

    account = mobile_account(unit.property.owner_id)
    if account is not None:
        if account.kind == PaymentAccount.Kind.TILL:
            return account.number, ""
        return account.number, f"{account.account_prefix}{unit.unit_number}"
    if settings.RENT_ACCOUNT_PREFIX:
        return settings.RENT_PAYBILL, f"{settings.RENT_ACCOUNT_PREFIX}{unit.unit_number}"
    return settings.RENT_PAYBILL, unit.payment_code


def receipt_text(parts: list, credit=None) -> str:
    """The receipt for a payment the landlord recorded, which may have cleared
    more than one bill: one item per line, like the bill, and only plain SMS
    characters (see bill_text)."""
    first = parts[0]
    tenancy = first.invoice.tenancy
    unit = tenancy.unit
    total = sum((part.amount for part in parts), credit.amount if credit else Decimal("0"))
    how = {
        Payment.Method.MPESA: f"M-Pesa code: {first.mpesa_receipt_number}",
        Payment.Method.BANK: f"Bank ref: {first.bank_reference}",
        Payment.Method.CASH: "Paid by: Cash",
    }[first.method]
    paid_on = timezone.localtime(first.paid_at)
    lines = [
        f"Hi {tenancy.tenant.first_name},",
        "Payment received. Thank you.",
        "",
        f"{unit.property.name} {unit.unit_number}",
        f"Amount: KES {total:,.0f}",
        how,
        f"Confirmed: {paid_on.day} {paid_on:%b %Y}",
        "",
    ]
    for part in parts:
        bill = part.invoice
        month = f"{bill.period_start:%B}"
        lines.append(f"{month} bill: KES {bill.balance:,.0f} left" if bill.balance > 0 else f"{month} bill: fully paid")
    if credit:
        lines.append(f"Kept for next bill: KES {credit.amount:,.0f}")
    return "\n".join(lines)


def how_to_pay(unit) -> str:
    number, account = pay_to(unit)
    if not account:
        return f"Pay via M-Pesa Till {number}."
    return f"Pay via M-Pesa Paybill {number}, Acc: {account}."


def prompts_allowed(unit) -> bool:
    """Whether a tenant of this unit can be sent an M-Pesa prompt.

    WHY not when the landlord has a paybill of their own: the prompt is sent
    through the platform's shortcode, so it would pay the platform rather than
    the landlord.
    """
    from django.conf import settings

    return settings.STK_PUSH_ENABLED and mobile_account(unit.property.owner_id) is None


def create_move_in_invoice(tenancy):
    """Raise the tenant's first invoice: the first month's rent and the
    property's fixed extras, plus the deposit if not already handed over.

    WHY one invoice with line items rather than two invoices: the tenant pays
    once to move in, and the invoice table is unique on (tenancy, period_start),
    so a second invoice for the same month could not exist anyway. Splitting the
    figures into line items keeps the deposit visible and auditable without
    pretending it is a separate debt.

    Idempotent: called again for the same tenancy and month it returns the
    invoice already there rather than raising a second one.

    WHY no SMS: a landlord adding a tenant is setting up their records, and a
    "welcome" text with a bill surprised tenants. The bill reaches them when
    the landlord sends bills or a reminder.
    """
    from django.utils import timezone
    import uuid

    from .billing import flat_charge_lines
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
    extras = flat_charge_lines(tenancy.unit)

    with transaction.atomic():
        invoice, created = Invoice.objects.get_or_create(
            tenancy=tenancy,
            period_start=period_start,
            defaults={
                "invoice_number": f"INV-{period_start.strftime('%Y%m')}-{uuid.uuid4().hex[:6].upper()}",
                "amount_due": rent + deposit + sum((line["amount"] for line in extras), Decimal("0")),
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
        InvoiceLineItem.objects.bulk_create(InvoiceLineItem(invoice=invoice, **line) for line in extras)
        apply_credit(tenancy)
        invoice.refresh_from_db()

    return invoice, True


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
