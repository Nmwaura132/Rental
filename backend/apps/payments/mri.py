"""Monthly Rental Income (MRI) figures for KRA filing.

Produces the two things a landlord needs on or before the 20th of the following
month: the rent roll eRITS expects per property, and the gross rent actually
received in the period with the tax due on it.

Deliberately reports rent RECEIVED, not rent INVOICED. MRI is charged on gross
rent received, so billing a tenant who has not paid must not create a tax
liability that month.
"""

from decimal import Decimal

from django.conf import settings
from django.db.models import Sum

from apps.payments.models import Payment


def _rate() -> Decimal:
    """The MRI rate as a fraction.

    WHY configurable rather than a constant: the rate has already moved once
    (10% to 7.5% in January 2024) and the Finance Bill 2026 proposed moving it
    back to 10%. Hard-coding it guarantees a silently wrong tax figure the next
    time Parliament changes its mind.
    """
    return Decimal(str(settings.MRI_TAX_RATE))


def rent_roll(*, owner, period_start, period_end):
    """Per-tenancy rent actually received in the period, for eRITS.

    Includes the tenant KRA PIN because eRITS ties each registered property to
    the PIN of whoever occupies it.
    """
    payments = (
        Payment.objects.filter(
            invoice__tenancy__unit__property__owner=owner,
            status=Payment.Status.CONFIRMED,
            paid_at__date__gte=period_start,
            paid_at__date__lte=period_end,
        )
        .select_related(
            "invoice__tenancy__tenant",
            "invoice__tenancy__unit__property",
        )
        .order_by("invoice__tenancy__unit__property__name", "invoice__tenancy__unit__unit_number")
    )

    rows: dict[int, dict] = {}
    for payment in payments:
        tenancy = payment.invoice.tenancy
        row = rows.setdefault(
            tenancy.id,
            {
                "tenancy_id": tenancy.id,
                "property": tenancy.unit.property.name,
                "lr_number": tenancy.unit.property.lr_number,
                "unit": tenancy.unit.unit_number,
                "tenant": f"{tenancy.tenant.first_name} {tenancy.tenant.last_name}".strip(),
                "tenant_kra_pin": tenancy.tenant.kra_pin or "",
                "agreed_rent": tenancy.rent_amount,
                "rent_received": Decimal("0"),
            },
        )
        row["rent_received"] += payment.amount

    return list(rows.values())


def mri_summary(*, owner, period_start, period_end):
    """Gross rent received and the MRI due on it for one period."""
    gross = (
        Payment.objects.filter(
            invoice__tenancy__unit__property__owner=owner,
            status=Payment.Status.CONFIRMED,
            paid_at__date__gte=period_start,
            paid_at__date__lte=period_end,
        ).aggregate(total=Sum("amount"))["total"]
        or Decimal("0")
    )

    rate = _rate()
    rows = rent_roll(owner=owner, period_start=period_start, period_end=period_end)
    missing_pins = [r["tenant"] for r in rows if not r["tenant_kra_pin"]]

    return {
        "period_start": period_start,
        "period_end": period_end,
        "gross_rent_received": gross,
        "tax_rate": rate,
        "tax_due": (gross * rate).quantize(Decimal("0.01")),
        "rent_roll": rows,
        # Surfaced rather than silently omitted: a filing missing tenant PINs is
        # the specific thing eRITS rejects, and the landlord can still chase them.
        "tenants_missing_kra_pin": missing_pins,
    }
