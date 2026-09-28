"""What goes on a tenant's monthly bill besides rent.

Flat charges (garbage, security, service) are billed for the month itself.
Metered charges (water, electricity) are billed in arrears: the bill raised on
1 October carries September's usage, read at the end of September.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.db import transaction

from .models import Invoice, InvoiceLineItem
from .services import invoice_status_for


def previous_month(period_start):
    return (period_start - timedelta(days=1)).replace(day=1)


def next_month(period_start):
    return (period_start + timedelta(days=32)).replace(day=1)


def charge_lines(unit, period_start) -> list[dict]:
    """Line items for the bill covering `period_start`, excluding rent."""
    from apps.properties.models import PropertyCharge

    lines = []
    for charge in PropertyCharge.objects.filter(property=unit.property, is_active=True):
        if charge.billing_method == PropertyCharge.BillingMethod.FLAT:
            lines.append({
                "description": charge.name,
                "charge_type": charge.charge_type,
                "amount": charge.unit_price,
            })
            continue
        line = metered_line(unit, charge, previous_month(period_start))
        if line:
            lines.append(line)
    return lines


def metered_line(unit, charge, usage_period) -> dict | None:
    """Usage over `usage_period`, or None if it cannot be worked out yet.

    None both when the month has no reading and when it is the meter's first
    reading, which only sets the baseline.
    """
    from apps.properties.models import MeterReading

    current = MeterReading.objects.filter(unit=unit, charge=charge, period=usage_period).first()
    previous = current.previous() if current else None
    if previous is None:
        return None
    used = current.reading - previous.reading
    return {
        "description": f"{charge.name} — {usage_period:%B}",
        "charge_type": charge.charge_type,
        "previous_reading": previous.reading,
        "current_reading": current.reading,
        "units_consumed": used,
        "unit_price": charge.unit_price,
        "amount": (used * charge.unit_price).quantize(Decimal("0.01")),
    }


def bill_late_reading(reading) -> list[tuple[Invoice, dict]]:
    """Add usage to bills already raised before the reading was entered.

    WHY: the bill goes out on the 1st whether or not every meter has been
    read, so a reading entered on the 3rd would otherwise never be charged.
    Returns each changed bill with the line added, so the tenant can be told.
    """
    from apps.tenants.models import Tenancy

    line = metered_line(reading.unit, reading.charge, reading.period)
    if line is None or line["amount"] <= 0:
        return []

    changed = []
    bills = Invoice.objects.filter(
        tenancy__unit=reading.unit,
        tenancy__status=Tenancy.Status.ACTIVE,
        period_start=next_month(reading.period),
    ).exclude(status=Invoice.Status.CANCELLED)
    for bill in bills:
        with transaction.atomic():
            bill = Invoice.objects.select_for_update().get(pk=bill.pk)
            if bill.line_items.filter(
                charge_type=reading.charge.charge_type,
                current_reading__isnull=False,
            ).exists():
                continue
            InvoiceLineItem.objects.create(invoice=bill, **line)
            bill.amount_due += line["amount"]
            bill.status = invoice_status_for(bill)
            bill.save(update_fields=["amount_due", "status", "updated_at"])
            changed.append((bill, line))
    return changed
