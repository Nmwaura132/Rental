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

from apps.payments.models import Payment


def _rate() -> Decimal:
    """The MRI rate as a fraction.

    WHY configurable rather than a constant: the rate has already moved once
    (10% to 7.5% in January 2024) and the Finance Bill 2026 proposed moving it
    back to 10%. Hard-coding it guarantees a silently wrong tax figure the next
    time Parliament changes its mind.
    """
    return Decimal(str(settings.MRI_TAX_RATE))


def _payments_in(owner, period_start, period_end):
    return (
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


def _rent_share(payment, cache: dict) -> Decimal:
    """How much of a payment was rent.

    WHY: a bill now carries water, garbage and — on move-in — the deposit
    alongside rent, and MRI is tax on rent alone. The deposit is refundable
    security, not income. Counting whole payments overstated the tax.

    Payments on a bill are taken as settling rent first, then the other
    charges; anything paid beyond the whole bill is rent paid in advance, which
    MRI taxes when it is received. That is the reading that declares the most
    rent, so if it is wrong, it is wrong in KRA's favour, not the landlord's.
    """
    invoice = payment.invoice
    if invoice.pk not in cache:
        lines = list(invoice.line_items.all())
        # A bill with no lines predates itemised billing and was rent only.
        rent_due = (
            sum((line.amount for line in lines if line.charge_type == "rent"), Decimal("0"))
            if lines else invoice.amount_due
        )
        other_due = invoice.amount_due - rent_due
        shares = {}
        for earlier in invoice.payments.filter(status=Payment.Status.CONFIRMED).order_by("paid_at", "id"):
            left = earlier.amount
            to_rent = min(left, max(rent_due, Decimal("0")))
            left -= to_rent
            rent_due -= to_rent
            to_other = min(left, max(other_due, Decimal("0")))
            left -= to_other
            other_due -= to_other
            shares[earlier.pk] = to_rent + left
        cache[invoice.pk] = shares
    return cache[invoice.pk].get(payment.pk, Decimal("0"))


def _rent_payments(owner, period_start, period_end):
    """(payment, rent share) for every payment in the period that included rent."""
    cache = {}
    for payment in _payments_in(owner, period_start, period_end):
        share = _rent_share(payment, cache)
        if share > 0:
            yield payment, share


def rent_roll(*, owner, period_start, period_end):
    """Per-tenancy rent actually received in the period, for eRITS.

    Includes the tenant KRA PIN because eRITS ties each registered property to
    the PIN of whoever occupies it.
    """
    rows: dict[int, dict] = {}
    for payment, share in _rent_payments(owner, period_start, period_end):
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
                "etims_receipts": [],
            },
        )
        row["rent_received"] += share
        # KRA cross-checks what is declared here against their eTIMS records, so
        # the row carries the receipts backing it. A month settled in parts can
        # sit under one receipt, hence the de-duplication.
        if payment.etims_receipt_number and (
            payment.etims_receipt_number not in row["etims_receipts"]
        ):
            row["etims_receipts"].append(payment.etims_receipt_number)

    return list(rows.values())


def mri_summary(*, owner, period_start, period_end):
    """Gross rent received and the MRI due on it for one period."""
    rent_payments = list(_rent_payments(owner, period_start, period_end))
    gross = sum((share for _, share in rent_payments), Decimal("0"))

    rate = _rate()
    rows = rent_roll(owner=owner, period_start=period_start, period_end=period_end)
    missing_pins = [r["tenant"] for r in rows if not r["tenant_kra_pin"]]
    unreceipted = sum(1 for payment, _ in rent_payments if not payment.etims_receipt_number)

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
        # Rent declared with no eTIMS receipt behind it is precisely the
        # mismatch KRA looks for, so it is counted where the landlord will see
        # it before filing rather than after.
        "payments_missing_etims_receipt": unreceipted,
    }
