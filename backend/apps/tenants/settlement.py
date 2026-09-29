"""Settling a tenant's deposit when they move out.

The agreement: the deposit "is refundable upon giving one month notice and the
Tenant leaving the premises, less any outstanding arrears, charges on repairs
or bills", and is forfeit if the tenant does not vacate before the next
payment month.

Order of use: the deposit first settles unpaid bills, oldest first; what is
left covers the landlord's deductions; anything remaining is refunded.
"""
from __future__ import annotations

from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from apps.payments.models import Invoice, Payment, TenancyCredit
from apps.payments.services import apply_confirmed_payment, apply_credit, credit_remaining

from .models import DepositSettlement, SettlementDeduction, Tenancy

_OPEN = [Invoice.Status.PENDING, Invoice.Status.PARTIALLY_PAID, Invoice.Status.OVERDUE]


def can_settle(tenancy) -> bool:
    """Only once the tenant is leaving: ended, or on the last day of notice."""
    if tenancy.status == Tenancy.Status.TERMINATED:
        return True
    return (
        tenancy.notice_effective_date is not None
        and tenancy.notice_effective_date <= timezone.localdate()
    )


def unpaid_bills(tenancy):
    return list(
        Invoice.objects.filter(tenancy=tenancy, status__in=_OPEN).order_by("due_date", "id")
    )


def preview(tenancy) -> dict:
    """The figures before any deductions, for the landlord to start from."""
    held = tenancy.deposit_amount if tenancy.deposit_paid else Decimal("0")
    bills = unpaid_bills(tenancy)
    arrears = sum((b.balance for b in bills), Decimal("0"))
    return {
        "deposit_held": held,
        "arrears": arrears,
        "unpaid_bills": [
            {"id": b.id, "invoice_number": b.invoice_number, "balance": b.balance, "due_date": b.due_date}
            for b in bills
        ],
        "available_after_arrears": max(held - arrears, Decimal("0")),
        "credit": credit_remaining(tenancy),
        "can_settle": can_settle(tenancy),
    }


def _clean_deductions(deductions) -> list[tuple[str, Decimal]]:
    cleaned = []
    for item in deductions or []:
        description = str(item.get("description") or "").strip()[:120]
        try:
            amount = Decimal(str(item.get("amount")))
        except Exception:
            raise ValidationError("Each deduction needs an amount.")
        if not description:
            raise ValidationError("Each deduction needs a description.")
        if amount <= 0:
            raise ValidationError(f"The deduction for {description} must be more than zero.")
        cleaned.append((description, amount.quantize(Decimal("0.01"))))
    return cleaned


def settle(tenancy, *, by, deductions=(), forfeited=False, notes="") -> DepositSettlement:
    """Record the settlement, apply the deposit to unpaid bills, and fix the refund.

    Raises ValidationError if the tenancy cannot be settled yet or already has been.
    """
    if not can_settle(tenancy):
        raise ValidationError("The deposit can be settled once the tenant has moved out.")
    if DepositSettlement.objects.filter(tenancy=tenancy).exists():
        raise ValidationError("This deposit has already been settled.")
    notes = (notes or "").strip()
    if forfeited and not notes:
        raise ValidationError("Say why the deposit is forfeited — the tenant is sent this.")

    cleaned = _clean_deductions(deductions)
    held = tenancy.deposit_amount if tenancy.deposit_paid else Decimal("0")

    with transaction.atomic():
        # Locks the row so two taps on "settle" cannot both get past the check above.
        Tenancy.objects.select_for_update().get(pk=tenancy.pk)
        if DepositSettlement.objects.filter(tenancy=tenancy).exists():
            raise ValidationError("This deposit has already been settled.")

        # Rent paid ahead is the tenant's own money and settles unpaid bills
        # before the deposit does.
        apply_credit(tenancy)

        remaining = held
        applied = Decimal("0")
        for bill in unpaid_bills(tenancy):
            if remaining <= 0:
                break
            take = min(remaining, bill.balance)
            apply_confirmed_payment(
                invoice_id=bill.pk,
                method=Payment.Method.DEPOSIT,
                amount=take,
                idempotency_key=f"deposit:{tenancy.pk}:{bill.pk}",
                paid_at=timezone.now(),
                recorded_by=by,
            )
            remaining -= take
            applied += take

        arrears_left = sum((b.balance for b in unpaid_bills(tenancy)), Decimal("0"))
        deductions_total = sum((amount for _, amount in cleaned), Decimal("0"))

        # Forfeiture only means the leftover is kept rather than refunded. The
        # deposit still counts against the deductions, so a forfeiting tenant
        # is not charged twice for the same repairs.
        over_deposit = max(deductions_total - remaining, Decimal("0"))
        deposit_refund = Decimal("0") if forfeited else max(remaining - deductions_total, Decimal("0"))

        # Unused credit covers deductions the deposit could not, and the rest
        # goes back to the tenant — forfeiture does not touch it.
        credit = credit_remaining(tenancy)
        from_credit = min(over_deposit, credit)
        credit_returned = credit - from_credit
        TenancyCredit.objects.filter(tenancy=tenancy, remaining__gt=0).update(remaining=0)

        owes = arrears_left + over_deposit - from_credit
        refund = deposit_refund + credit_returned

        settlement = DepositSettlement.objects.create(
            tenancy=tenancy,
            deposit_held=held,
            applied_to_arrears=applied,
            deductions_total=deductions_total,
            refund_due=refund,
            tenant_owes=owes,
            credit_returned=credit_returned,
            forfeited=forfeited,
            notes=notes[:2000],
            settled_by=by,
        )
        SettlementDeduction.objects.bulk_create(
            SettlementDeduction(settlement=settlement, description=d, amount=a) for d, a in cleaned
        )

    transaction.on_commit(lambda: _send_statement(settlement))
    return settlement


def mark_refunded(settlement, *, method, reference=""):
    if settlement.refunded_at:
        raise ValidationError("This refund was already recorded.")
    if settlement.refund_due <= 0:
        raise ValidationError("There is no refund due on this deposit.")
    method = (method or "").strip()
    if method not in {"cash", "mpesa", "bank"}:
        raise ValidationError("Refund method must be cash, mpesa or bank.")
    settlement.refunded_at = timezone.now()
    settlement.refund_method = method
    settlement.refund_reference = (reference or "").strip()[:100]
    settlement.save(update_fields=["refunded_at", "refund_method", "refund_reference"])
    return settlement


def _send_statement(settlement):
    """An itemised statement to the tenant, since this is where disputes start."""
    from apps.notifications.tasks import send_sms

    tenancy = settlement.tenancy
    parts = [f"Deposit KES {settlement.deposit_held:,.0f}"]
    if settlement.applied_to_arrears:
        parts.append(f"unpaid rent -{settlement.applied_to_arrears:,.0f}")
    for deduction in settlement.deductions.all():
        parts.append(f"{deduction.description} -{deduction.amount:,.0f}")
    if settlement.credit_returned:
        parts.append(f"unused credit +{settlement.credit_returned:,.0f}")

    if settlement.forfeited:
        outcome = f"The deposit is forfeited: {settlement.notes}"
    elif settlement.refund_due > 0:
        outcome = f"Refund due to you: KES {settlement.refund_due:,.0f}."
    else:
        outcome = "No refund is due."
    if settlement.tenant_owes > 0:
        outcome += f" You still owe KES {settlement.tenant_owes:,.0f}."

    unit = tenancy.unit
    send_sms.delay(
        tenancy.tenant_id,
        f"Dear {tenancy.tenant.first_name}, your deposit for {unit.property.name} "
        f"Unit {unit.unit_number} has been settled: {'; '.join(parts)}. {outcome}",
    )
