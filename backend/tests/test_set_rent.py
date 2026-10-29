"""Changing a house's rent: a mistake, or one house charged differently."""
from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from rest_framework.test import APIClient

from apps.payments.models import Invoice
from apps.payments.tasks import bill_month


SETTLEMENT = {
    "deposit_held": Decimal("15000"), "applied_to_arrears": Decimal("0"), "deductions_total": Decimal("0"),
    "refund_due": Decimal("15000"), "tenant_owes": Decimal("0"),
}


def _as(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


def _set(user, unit, amount):
    return _as(user).post(f"/api/v1/properties/units/{unit.id}/set-amounts/", {"rent_amount": amount}, format="json")


@pytest.mark.django_db
class TestChangingTheRent:
    def test_the_house_gets_the_new_rent(self, landlord, unit):
        _set(landlord, unit, "3000")
        unit.refresh_from_db()
        assert unit.rent_amount == Decimal("3000.00")

    def test_the_tenant_living_there_is_charged_it(self, landlord, unit, tenancy):
        _set(landlord, unit, "3000")
        tenancy.refresh_from_db()
        assert tenancy.rent_amount == Decimal("3000.00")

    def test_the_next_bill_uses_it(self, landlord, unit, tenancy):
        _set(landlord, unit, "3000")
        bill_month(date(2030, 1, 1))
        rent = Invoice.objects.get(period_start=date(2030, 1, 1)).line_items.get(charge_type="rent")
        assert rent.amount == Decimal("3000.00")

    def test_a_bill_already_sent_is_not_changed(self, landlord, unit, tenancy, invoice):
        before = invoice.amount_due
        _set(landlord, unit, "3000")
        invoice.refresh_from_db()
        assert invoice.amount_due == before

    def test_commas_are_fine(self, landlord, unit):
        assert _set(landlord, unit, "3,500").data["rent_amount"] == Decimal("3500.00")

    def test_it_says_whether_a_tenant_was_changed_too(self, landlord, unit, tenancy):
        assert _set(landlord, unit, "3000").data["tenancy_updated"] is True


@pytest.mark.django_db
class TestWhatIsRefused:
    def test_zero(self, landlord, unit):
        assert _set(landlord, unit, "0").status_code == 400

    def test_words(self, landlord, unit):
        assert _set(landlord, unit, "three thousand").status_code == 400

    def test_another_landlords_house(self, unit, django_user_model):
        other = django_user_model.objects.create_user(
            phone_number="+254700999002", password="Other@Test1", first_name="O", last_name="L",
            role=django_user_model.Role.LANDLORD,
        )
        assert _set(other, unit, "1").status_code == 404

    def test_the_tenant(self, tenant, unit, tenancy):
        assert _set(tenant, unit, "1").status_code == 403

    def test_a_caretaker(self, caretaker, unit):
        assert _set(caretaker, unit, "1").status_code == 403


def _deposit(user, unit, amount):
    return _as(user).post(f"/api/v1/properties/units/{unit.id}/set-amounts/", {"deposit_amount": amount}, format="json")


@pytest.mark.django_db
class TestChangingTheDeposit:
    def test_the_house_gets_the_new_deposit(self, landlord, unit):
        _deposit(landlord, unit, "5000")
        unit.refresh_from_db()
        assert unit.deposit_amount == Decimal("5000.00")

    def test_the_tenant_living_there_is_corrected_too(self, landlord, unit, tenancy):
        _deposit(landlord, unit, "5000")
        tenancy.refresh_from_db()
        assert tenancy.deposit_amount == Decimal("5000.00")

    def test_changing_the_deposit_leaves_the_rent(self, landlord, unit, tenancy):
        before = unit.rent_amount
        _deposit(landlord, unit, "5000")
        unit.refresh_from_db()
        assert unit.rent_amount == before

    def test_no_deposit_is_allowed(self, landlord, unit):
        assert _deposit(landlord, unit, "0").status_code == 200

    def test_a_negative_deposit_is_refused(self, landlord, unit):
        assert _deposit(landlord, unit, "-1").status_code == 400

    def test_both_at_once(self, landlord, unit, tenancy):
        _as(landlord).post(f"/api/v1/properties/units/{unit.id}/set-amounts/",
                           {"rent_amount": "3000", "deposit_amount": "6000"}, format="json")
        tenancy.refresh_from_db()
        assert (tenancy.rent_amount, tenancy.deposit_amount) == (Decimal("3000.00"), Decimal("6000.00"))

    def test_nothing_given_is_refused(self, landlord, unit):
        assert _as(landlord).post(f"/api/v1/properties/units/{unit.id}/set-amounts/", {}, format="json").status_code == 400

    def test_a_settled_deposit_is_not_changed(self, landlord, unit, tenancy):
        from apps.tenants.models import DepositSettlement

        DepositSettlement.objects.create(tenancy=tenancy, settled_by=landlord, **SETTLEMENT)
        assert _deposit(landlord, unit, "5000").status_code == 400
