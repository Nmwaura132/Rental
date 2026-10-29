"""The monthly bill SMS: a statement a tenant can check line by line."""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.billing import previous_month
from apps.payments.models import Invoice
from apps.payments.tasks import bill_text, generate_monthly_invoices
from apps.properties.models import MeterReading, PropertyCharge

THIS_MONTH = timezone.localdate().replace(day=1)
LAST_MONTH = previous_month(THIS_MONTH)
TWO_AGO = previous_month(LAST_MONTH)
# Basic SMS characters: a bill using only these costs one part per 153.
GSM7 = set(
    "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "ÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
)


@pytest.fixture
def water(property_):
    return PropertyCharge.objects.create(
        property=property_, charge_type="water", name="Water",
        billing_method=PropertyCharge.BillingMethod.METERED, unit_price=Decimal("40.00"),
    )


@pytest.fixture
def garbage(property_):
    return PropertyCharge.objects.create(
        property=property_, charge_type="garbage", name="Garbage",
        billing_method=PropertyCharge.BillingMethod.FLAT, unit_price=Decimal("200.00"),
    )


@pytest.fixture
def billed(tenancy, water, garbage, landlord):
    MeterReading.objects.create(unit=tenancy.unit, charge=water, period=TWO_AGO, reading=Decimal("1252"),
                                recorded_by=landlord, read_on=LAST_MONTH - timedelta(days=1))
    MeterReading.objects.create(unit=tenancy.unit, charge=water, period=LAST_MONTH, reading=Decimal("1268"),
                                recorded_by=landlord, read_on=THIS_MONTH - timedelta(days=1))
    generate_monthly_invoices()
    invoice = Invoice.objects.get(tenancy=tenancy, period_start=THIS_MONTH)
    return bill_text(tenancy, invoice).split("\n")


@pytest.mark.django_db
class TestTheBill:
    def test_it_is_set_out_line_by_line(self, billed):
        assert len(billed) > 10

    def test_it_greets_the_tenant(self, billed, tenant):
        assert billed[0] == f"Hi {tenant.first_name},"

    def test_it_names_the_month(self, billed):
        assert billed[2] == f"{THIS_MONTH:%B %Y} bill"

    def test_water_shows_the_earlier_reading_and_when(self, billed):
        assert f" {LAST_MONTH - timedelta(days=1):%d %b}: 1,252" in billed

    def test_water_shows_the_latest_reading_and_when(self, billed):
        assert f" {THIS_MONTH - timedelta(days=1):%d %b}: 1,268" in billed

    def test_water_shows_the_working(self, billed):
        assert " Used 16 x 40" in billed

    def test_water_is_charged_what_the_working_says(self, billed):
        assert "Water: 640" in billed

    def test_it_says_where_to_pay(self, billed):
        assert any(line.startswith("Pay: M-Pesa") for line in billed)

    def test_it_uses_only_basic_sms_characters(self, billed):
        assert set("\n".join(billed)) <= GSM7

    def test_it_fits_in_three_sms(self, billed):
        assert len("\n".join(billed)) <= 3 * 153


@pytest.mark.django_db
class TestReadOn:
    def _post(self, landlord, unit, water, **extra):
        api = APIClient()
        api.force_authenticate(user=landlord)
        return api.post(
            "/api/v1/properties/meter-readings/",
            {"unit": unit.id, "charge": water.id, "period": str(LAST_MONTH), "reading": "130", **extra},
            format="json",
        )

    def test_it_defaults_to_today(self, landlord, unit, water):
        self._post(landlord, unit, water)
        assert MeterReading.objects.get().read_on == timezone.localdate()

    def test_a_reading_typed_in_late_keeps_the_day_it_was_read(self, landlord, unit, water):
        self._post(landlord, unit, water, read_on=str(THIS_MONTH - timedelta(days=1)))
        assert MeterReading.objects.get().read_on == THIS_MONTH - timedelta(days=1)

    def test_a_day_still_to_come_is_refused(self, landlord, unit, water):
        response = self._post(landlord, unit, water, read_on=str(timezone.localdate() + timedelta(days=1)))
        assert response.status_code == 400
