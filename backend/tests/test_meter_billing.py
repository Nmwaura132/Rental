"""Water and other charges on the monthly bill.

Flat charges are billed for the month; metered usage in arrears — the bill on
1 October carries September's water, read at the end of September.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.billing import previous_month
from apps.payments.models import Invoice
from apps.payments.tasks import generate_monthly_invoices
from apps.properties.models import MeterReading, PropertyCharge

THIS_MONTH = timezone.localdate().replace(day=1)
LAST_MONTH = previous_month(THIS_MONTH)
TWO_AGO = previous_month(LAST_MONTH)


@pytest.fixture
def sent(monkeypatch):
    captured = []
    from apps.notifications import tasks as ntasks

    monkeypatch.setattr(ntasks.send_sms, "delay", lambda uid, msg: captured.append((uid, msg)))
    return captured


@pytest.fixture
def water(property_):
    return PropertyCharge.objects.create(
        property=property_, charge_type="water", name="Water",
        billing_method=PropertyCharge.BillingMethod.METERED, unit_price=Decimal("100.00"),
    )


@pytest.fixture
def garbage(property_):
    return PropertyCharge.objects.create(
        property=property_, charge_type="garbage", name="Garbage",
        billing_method=PropertyCharge.BillingMethod.FLAT, unit_price=Decimal("200.00"),
    )


def _read(unit, charge, period, value, by):
    return MeterReading.objects.create(
        unit=unit, charge=charge, period=period, reading=Decimal(value), recorded_by=by,
    )


def _bill(tenancy):
    return Invoice.objects.get(tenancy=tenancy, period_start=THIS_MONTH)


def _client(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


class TestTheMonthlyBill:
    def test_a_flat_charge_is_on_the_bill(self, tenancy, garbage, sent):
        generate_monthly_invoices()
        assert _bill(tenancy).line_items.filter(charge_type="garbage").exists()

    def test_last_months_water_is_billed(self, tenancy, water, landlord, sent):
        _read(tenancy.unit, water, TWO_AGO, "100", landlord)
        _read(tenancy.unit, water, LAST_MONTH, "130", landlord)
        generate_monthly_invoices()
        assert _bill(tenancy).line_items.get(charge_type="water").amount == Decimal("3000.00")

    def test_the_bill_totals_rent_and_charges(self, tenancy, water, garbage, landlord, sent):
        _read(tenancy.unit, water, TWO_AGO, "100", landlord)
        _read(tenancy.unit, water, LAST_MONTH, "130", landlord)
        generate_monthly_invoices()
        assert _bill(tenancy).amount_due == tenancy.rent_amount + Decimal("3200.00")

    def test_a_first_reading_only_sets_the_baseline(self, tenancy, water, landlord, sent):
        _read(tenancy.unit, water, LAST_MONTH, "130", landlord)
        generate_monthly_invoices()
        assert not _bill(tenancy).line_items.filter(charge_type="water").exists()

    def test_the_bill_sms_itemises_the_charges(self, tenancy, garbage, sent):
        generate_monthly_invoices()
        assert "Garbage 200" in sent[0][1]


class TestAReadingEnteredAfterTheBill:
    def _late(self, tenancy, water, landlord):
        _read(tenancy.unit, water, TWO_AGO, "100", landlord)
        generate_monthly_invoices()
        return _client(landlord).post(
            "/api/v1/properties/meter-readings/",
            {"unit": tenancy.unit.id, "charge": water.id, "period": str(LAST_MONTH), "reading": "130"},
            format="json",
        )

    def test_the_usage_is_added_to_the_bill(self, tenancy, water, landlord, sent):
        self._late(tenancy, water, landlord)
        assert _bill(tenancy).amount_due == tenancy.rent_amount + Decimal("3000.00")

    def test_the_tenant_is_told(self, tenancy, water, landlord, sent, tenant):
        self._late(tenancy, water, landlord)
        assert "has been updated" in sent[-1][1] and sent[-1][0] == tenant.id

    def test_it_is_not_added_twice(self, tenancy, water, landlord, sent):
        from apps.payments.billing import bill_late_reading

        self._late(tenancy, water, landlord)
        bill_late_reading(MeterReading.objects.get(period=LAST_MONTH))
        assert _bill(tenancy).line_items.filter(charge_type="water").count() == 1

    def test_a_billed_reading_cannot_be_changed(self, tenancy, water, landlord, sent):
        self._late(tenancy, water, landlord)
        reading = MeterReading.objects.get(period=LAST_MONTH)
        response = _client(landlord).patch(
            f"/api/v1/properties/meter-readings/{reading.id}/", {"reading": "140"}, format="json",
        )
        assert response.status_code == 403


class TestEnteringReadings:
    def _post(self, user, unit, water, value, period=LAST_MONTH):
        return _client(user).post(
            "/api/v1/properties/meter-readings/",
            {"unit": unit.id, "charge": water.id, "period": str(period), "reading": value},
            format="json",
        )

    def test_a_reading_lower_than_last_month_is_refused(self, unit, water, landlord):
        _read(unit, water, TWO_AGO, "130", landlord)
        assert self._post(landlord, unit, water, "120").status_code == 400

    def test_the_caretaker_can_record_readings(self, unit, water, caretaker, property_):
        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        assert self._post(caretaker, unit, water, "130").status_code == 201

    def test_a_tenant_cannot(self, unit, water, tenant):
        assert self._post(tenant, unit, water, "130").status_code == 403

    def test_the_sheet_carries_last_months_reading_forward(self, unit, water, landlord, property_):
        _read(unit, water, TWO_AGO, "100", landlord)
        response = _client(landlord).get(
            f"/api/v1/properties/meter-readings/sheet/?property={property_.id}&period={LAST_MONTH}"
        )
        assert Decimal(str(response.data["rows"][0]["previous_reading"])) == Decimal("100")


class TestTheReminderOnThe28th:
    def test_a_missing_reading_is_chased(self, tenancy, water, sent, landlord):
        from apps.notifications.tasks import remind_missing_meter_readings

        remind_missing_meter_readings()
        assert sent[0][0] == landlord.id

    def test_the_caretaker_is_told_too(self, tenancy, water, sent, caretaker, property_):
        from apps.notifications.tasks import remind_missing_meter_readings

        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        remind_missing_meter_readings()
        assert caretaker.id in {uid for uid, _ in sent}

    def test_nothing_is_sent_once_every_unit_is_read(self, tenancy, water, sent, landlord):
        from apps.notifications.tasks import remind_missing_meter_readings

        _read(tenancy.unit, water, THIS_MONTH, "130", landlord)
        remind_missing_meter_readings()
        assert sent == []
