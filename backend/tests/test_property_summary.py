"""The figures behind the Kasa 2.0 screens, and who may see them.

The design keeps money to the landlord: a caretaker sees each unit's status
but no totals or balances, and a tenant sees nothing about their neighbours.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

import pytest
from django.core.cache import cache
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.models import Invoice
from apps.properties.models import Unit
from apps.properties.summary import property_summary, unit_states
from apps.tenants.models import Tenancy

MONTH = timezone.localdate().replace(day=1)


@pytest.fixture(autouse=True)
def fresh_cache():
    cache.clear()


def _bill(tenancy, amount, *, months_ago=0, paid="0", overdue=False, number=None):
    start = (MONTH - timedelta(days=31 * months_ago)).replace(day=1)
    bill = Invoice.objects.create(
        tenancy=tenancy, invoice_number=number or f"INV-{start:%Y%m}-{tenancy.pk}",
        amount_due=Decimal(amount), amount_paid=Decimal(paid),
        due_date=start.replace(day=5), period_start=start, period_end=start + timedelta(days=27),
    )
    if overdue:
        bill.status = Invoice.Status.OVERDUE
        bill.save(update_fields=["status"])
    return bill


@pytest.fixture
def vacant(property_):
    return Unit.objects.create(
        property=property_, unit_number="V1", unit_type=Unit.UnitType.BEDSITTER,
        rent_amount=Decimal("10000"), deposit_amount=Decimal("10000"),
    )


def _client(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


class TestUnitStates:
    def test_an_empty_unit_is_vacant(self, property_, vacant):
        assert unit_states(property_)[vacant.id]["state"] == "vacant"

    def test_a_paid_up_tenant_is_paid(self, tenancy):
        assert unit_states(tenancy.unit.property)[tenancy.unit_id]["state"] == "paid"

    def test_an_open_bill_is_due(self, tenancy):
        _bill(tenancy, "15000")
        assert unit_states(tenancy.unit.property)[tenancy.unit_id]["state"] == "due"

    def test_an_overdue_bill_is_arrears(self, tenancy):
        _bill(tenancy, "15000", months_ago=1, overdue=True)
        assert unit_states(tenancy.unit.property)[tenancy.unit_id]["state"] == "arrears"

    def test_notice_outranks_arrears(self, tenancy):
        _bill(tenancy, "15000", months_ago=1, overdue=True)
        tenancy.notice_effective_date = timezone.localdate() + timedelta(days=20)
        tenancy.save(update_fields=["notice_effective_date"])
        assert unit_states(tenancy.unit.property)[tenancy.unit_id]["state"] == "notice"


class TestPropertySummary:
    def test_collected_is_against_this_months_bills(self, tenancy):
        _bill(tenancy, "20000", paid="15000")
        assert property_summary(tenancy.unit.property)["collected_pct"] == 75

    def test_an_overpaid_bill_does_not_push_past_100(self, tenancy):
        _bill(tenancy, "20000", paid="25000")
        assert property_summary(tenancy.unit.property)["collected_pct"] == 100

    def test_arrears_include_earlier_months(self, tenancy):
        _bill(tenancy, "15000", months_ago=2, paid="5000", overdue=True, number="INV-A")
        _bill(tenancy, "15000", months_ago=1, overdue=True, number="INV-B")
        assert property_summary(tenancy.unit.property)["arrears"] == Decimal("25000")

    def test_no_bills_yet_is_not_zero_percent(self, tenancy):
        # Nothing expected is not the same as nothing collected.
        assert property_summary(tenancy.unit.property)["collected_pct"] is None

    def test_counts_occupancy(self, tenancy, vacant):
        summary = property_summary(tenancy.unit.property)
        assert (summary["occupied"], summary["vacant"]) == (1, 1)


class TestWhoSeesWhat:
    def _property(self, user, property_):
        return _client(user).get(f"/api/v1/properties/{property_.id}/").data

    def test_the_landlord_sees_money(self, landlord, tenancy):
        data = self._property(landlord, tenancy.unit.property)
        assert "arrears" in data["summary"]

    def test_the_landlord_sees_each_units_balance(self, landlord, tenancy):
        _bill(tenancy, "15000")
        unit = self._property(landlord, tenancy.unit.property)["units"][0]
        assert Decimal(str(unit["balance"])) == Decimal("15000")

    def test_a_caretaker_sees_who_is_in_a_unit(self, caretaker, tenancy):
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        assert self._property(caretaker, prop)["units"][0]["state"] == "occupied"

    def test_a_caretaker_is_not_told_who_is_behind_on_rent(self, caretaker, tenancy):
        _bill(tenancy, "15000", months_ago=1, overdue=True)
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        assert self._property(caretaker, prop)["units"][0]["state"] == "occupied"

    def test_a_caretaker_is_not_told_how_many_bills_are_overdue(self, caretaker, tenancy):
        _bill(tenancy, "15000", months_ago=1, overdue=True)
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        assert "overdue_bills" not in self._property(caretaker, prop)["summary"]

    def test_a_caretaker_still_sees_who_is_leaving(self, caretaker, tenancy):
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        tenancy.notice_effective_date = timezone.localdate() + timedelta(days=20)
        tenancy.save(update_fields=["notice_effective_date"])
        assert self._property(caretaker, prop)["units"][0]["state"] == "notice"

    def test_a_landlord_still_sees_arrears(self, landlord, tenancy):
        _bill(tenancy, "15000", months_ago=1, overdue=True)
        assert self._property(landlord, tenancy.unit.property)["units"][0]["state"] == "arrears"

    def test_a_caretaker_sees_no_money(self, caretaker, tenancy):
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        data = self._property(caretaker, prop)
        assert ("arrears" in data["summary"], "balance" in data["units"][0]) == (False, False)

    def test_a_tenant_sees_nothing_about_the_building(self, tenant, tenancy):
        data = self._property(tenant, tenancy.unit.property)
        assert ("summary" in data, "state" in data["units"][0]) == (False, False)


class TestTheDashboard:
    def test_the_landlord_gets_expected_this_month(self, landlord, tenancy):
        _bill(tenancy, "15000")
        data = _client(landlord).get("/api/v1/payments/dashboard/").data
        assert Decimal(str(data["expected_this_month_kes"])) == Decimal("15000")

    def test_the_landlord_gets_how_old_the_oldest_arrears_are(self, landlord, tenancy):
        bill = _bill(tenancy, "15000", months_ago=1, overdue=True)
        data = _client(landlord).get("/api/v1/payments/dashboard/").data
        assert data["oldest_overdue_days"] == (timezone.localdate() - bill.due_date).days

    def test_a_caretaker_gets_no_money(self, caretaker, tenancy):
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        data = _client(caretaker).get("/api/v1/payments/dashboard/").data
        assert not any(key.endswith("_kes") for key in data)

    def test_a_caretaker_gets_their_day(self, caretaker, tenancy):
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        tenancy.notice_effective_date = timezone.localdate() + timedelta(days=10)
        tenancy.save(update_fields=["notice_effective_date"])
        data = _client(caretaker).get("/api/v1/payments/dashboard/").data
        assert data["moving_out"][0]["unit"] == tenancy.unit.unit_number

    def test_a_caretaker_is_told_about_meters_to_read(self, caretaker, tenancy):
        from apps.properties.models import PropertyCharge

        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        PropertyCharge.objects.create(
            property=prop, charge_type="water", name="Water",
            billing_method=PropertyCharge.BillingMethod.METERED, unit_price=Decimal("100"),
        )
        data = _client(caretaker).get("/api/v1/payments/dashboard/").data
        assert data["readings_left"] == 1


class TestThePaymentsList:
    def _pay(self, invoice, amount, days_ago, key):
        from apps.payments.models import Payment

        return Payment.objects.create(
            invoice=invoice, method=Payment.Method.MPESA, status=Payment.Status.CONFIRMED,
            amount=Decimal(amount), idempotency_key=key,
            paid_at=timezone.now() - timedelta(days=days_ago),
        )

    def test_each_payment_says_who_paid(self, landlord, invoice):
        self._pay(invoice, "5000", 1, "list:who")
        row = _client(landlord).get("/api/v1/payments/").data["results"][0]
        assert (row["tenant_name"], row["unit_number"]) == ("Test Tenant", invoice.tenancy.unit.unit_number)

    def test_newest_first(self, landlord, invoice):
        self._pay(invoice, "1000", 5, "list:old")
        self._pay(invoice, "2000", 1, "list:new")
        rows = _client(landlord).get("/api/v1/payments/").data["results"]
        assert [Decimal(r["amount"]) for r in rows] == [Decimal("2000"), Decimal("1000")]

    def test_another_landlord_sees_none_of_them(self, invoice, django_user_model):
        self._pay(invoice, "5000", 1, "list:private")
        stranger = django_user_model.objects.create_user(
            phone_number="+254700666777", password="Other@Test1",
            first_name="O", last_name="L", role=django_user_model.Role.LANDLORD,
        )
        assert _client(stranger).get("/api/v1/payments/").data["results"] == []
