"""What a landlord needs to see about a property at a glance.

Serves the Kasa 2.0 screens: the properties list (collected, arrears, counts)
and the unit grid (one status per unit). Kept out of the serializer so the
counting rules live in one place and are tested directly.
"""
from __future__ import annotations

from decimal import Decimal

from django.utils import timezone

from apps.payments.models import Invoice
from apps.tenants.models import Tenancy

_OPEN = [Invoice.Status.PENDING, Invoice.Status.PARTIALLY_PAID, Invoice.Status.OVERDUE]

# What a unit shows, most urgent first when more than one applies.
VACANT, NOTICE, ARREARS, DUE, PAID = "vacant", "notice", "arrears", "due", "paid"


def unit_states(property_) -> dict[int, dict]:
    """unit id -> {"state", "tenant", "balance"} for every unit in the property.

    Notice outranks arrears on the tile because it changes what the landlord
    does next (inspection, reletting); arrears still shows on the unit screen
    and in Money.
    """
    tenancies = {
        t.unit_id: t
        for t in Tenancy.objects.filter(unit__property=property_, status=Tenancy.Status.ACTIVE)
        .select_related("tenant")
    }
    open_bills: dict[int, list] = {}
    for bill in Invoice.objects.filter(tenancy__unit__property=property_, status__in=_OPEN):
        open_bills.setdefault(bill.tenancy_id, []).append(bill)

    states = {}
    for unit in property_.units.all():
        tenancy = tenancies.get(unit.id)
        if tenancy is None:
            states[unit.id] = {"state": VACANT, "tenant": None, "balance": Decimal("0")}
            continue
        bills = open_bills.get(tenancy.id, [])
        balance = sum((b.balance for b in bills), Decimal("0"))
        if tenancy.notice_effective_date is not None:
            state = NOTICE
        elif any(b.status == Invoice.Status.OVERDUE for b in bills):
            state = ARREARS
        elif balance > 0:
            state = DUE
        else:
            state = PAID
        states[unit.id] = {
            "state": state,
            "tenant": tenancy.tenant.get_full_name(),
            "balance": balance,
        }
    return states


def property_summary(property_, states=None) -> dict:
    """Occupancy, this month's collection and arrears for one property.

    "Expected" and "collected" are this month's bills and what has been paid
    against them, so the percentage answers "how much of this month's rent is
    in". Arrears is everything overdue, whatever month it is from.
    """
    states = states if states is not None else unit_states(property_)
    month = timezone.localdate().replace(day=1)
    this_month = Invoice.objects.filter(
        tenancy__unit__property=property_, period_start=month
    ).exclude(status=Invoice.Status.CANCELLED)
    expected = sum((b.amount_due for b in this_month), Decimal("0"))
    collected = sum((min(b.amount_paid, b.amount_due) for b in this_month), Decimal("0"))
    overdue = Invoice.objects.filter(
        tenancy__unit__property=property_, status=Invoice.Status.OVERDUE
    )
    counts = {s: 0 for s in (VACANT, NOTICE, ARREARS, DUE, PAID)}
    for info in states.values():
        counts[info["state"]] += 1

    return {
        "units": len(states),
        "occupied": len(states) - counts[VACANT],
        "vacant": counts[VACANT],
        "notice": counts[NOTICE],
        "overdue_bills": overdue.count(),
        "expected_this_month": expected,
        "collected_this_month": collected,
        "collected_pct": round(collected / expected * 100) if expected else None,
        "arrears": sum((b.balance for b in overdue), Decimal("0")),
    }


MONEY_KEYS = ("expected_this_month", "collected_this_month", "collected_pct", "arrears")

# What a caretaker may not see: the money, and how many bills are overdue, which
# says the same thing about who is behind.
CARETAKER_HIDDEN = MONEY_KEYS + ("overdue_bills",)

OCCUPIED = "occupied"


def without_payment_status(state: str | None) -> str | None:
    """A unit's state with what the tenant owes taken out of it.

    A caretaker sees who lives where and who is leaving, but never who is
    behind on rent: paid, due and arrears all read as plain "occupied".
    """
    return OCCUPIED if state in (PAID, DUE, ARREARS) else state
