"""Changing a house's rent: a mistake, or one house charged differently."""
from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from rest_framework.test import APIClient

from apps.payments.models import Invoice
from apps.payments.tasks import bill_month


def _as(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


def _set(user, unit, amount):
    return _as(user).post(f"/api/v1/properties/units/{unit.id}/set-rent/", {"rent_amount": amount}, format="json")


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
