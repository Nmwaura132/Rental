"""The unit screen's single read.

Assembled server-side because payments and maintenance cannot be filtered to a
tenancy, and opening those filters would let one landlord walk another's records.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.models import Payment
from apps.tenants.models import MaintenanceRequest


def _get(user, unit):
    client = APIClient()
    client.force_authenticate(user=user)
    return client.get(f"/api/v1/properties/units/{unit.id}/occupancy/")


@pytest.fixture
def occupied(tenancy, unit):
    unit.refresh_from_db()
    return unit


class TestVacantUnit:
    def test_a_vacant_unit_reports_no_tenancy(self, landlord, unit):
        assert _get(landlord, unit).data["tenancy"] is None

    def test_a_vacant_unit_reports_no_tenant(self, landlord, unit):
        assert _get(landlord, unit).data["tenant"] is None

    def test_a_vacant_unit_still_returns_the_unit(self, landlord, unit):
        assert _get(landlord, unit).data["unit"]["unit_number"] == unit.unit_number


class TestOccupiedUnit:
    def test_an_occupied_unit_returns_its_tenancy(self, landlord, occupied, tenancy):
        assert _get(landlord, occupied).data["tenancy"]["id"] == tenancy.id

    def test_the_tenant_name_is_returned(self, landlord, occupied):
        assert _get(landlord, occupied).data["tenant"]["name"] == "Test Tenant"

    def test_a_confirmed_payment_appears_in_the_history(
        self, landlord, occupied, invoice
    ):
        Payment.objects.create(
            invoice=invoice,
            method=Payment.Method.MPESA,
            status=Payment.Status.CONFIRMED,
            amount=Decimal("15000.00"),
            idempotency_key="occ:paid",
            paid_at=timezone.now(),
        )
        assert len(_get(landlord, occupied).data["payments"]) == 1

    def test_an_unconfirmed_payment_is_not_shown_as_history(
        self, landlord, occupied, invoice
    ):
        # Showing a pending payment as received would have a landlord think
        # rent had arrived when it had not.
        Payment.objects.create(
            invoice=invoice,
            method=Payment.Method.MPESA,
            status=Payment.Status.PENDING,
            amount=Decimal("15000.00"),
            idempotency_key="occ:pending",
        )
        assert _get(landlord, occupied).data["payments"] == []

    def test_a_maintenance_request_is_listed(self, landlord, occupied, tenancy):
        MaintenanceRequest.objects.create(
            tenancy=tenancy, title="Leaking tap", description="Kitchen sink."
        )
        assert len(_get(landlord, occupied).data["maintenance"]) == 1

    def test_notice_is_surfaced_on_the_tenancy(self, landlord, occupied, tenancy):
        tenancy.notice_given_at = timezone.now()
        tenancy.notice_effective_date = timezone.localdate() + timedelta(days=30)
        tenancy.save(update_fields=["notice_given_at", "notice_effective_date"])
        assert _get(landlord, occupied).data["tenancy"]["notice_effective_date"] is not None


class TestWhoSeesIdentityFields:
    def test_the_owner_sees_the_tenants_kra_pin(self, landlord, occupied, tenant):
        # They need it to file; that is the whole reason it is collected.
        tenant.kra_pin = "A012345678Z"
        tenant.save(update_fields=["kra_pin"])
        assert _get(landlord, occupied).data["tenant"]["kra_pin"] == "A012345678Z"

    def test_a_caretaker_does_not_see_the_kra_pin(
        self, caretaker, occupied, tenant, property_
    ):
        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        tenant.kra_pin = "A012345678Z"
        tenant.save(update_fields=["kra_pin"])
        assert "kra_pin" not in _get(caretaker, occupied).data["tenant"]

    def test_a_caretaker_does_not_see_the_national_id(
        self, caretaker, occupied, tenant, property_
    ):
        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        assert "national_id" not in _get(caretaker, occupied).data["tenant"]

    def test_a_caretaker_can_still_see_who_lives_there(
        self, caretaker, occupied, property_
    ):
        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        assert _get(caretaker, occupied).data["tenant"]["name"] == "Test Tenant"


class TestScoping:
    def test_another_landlord_cannot_read_the_unit(self, occupied, django_user_model):
        stranger = django_user_model.objects.create_user(
            phone_number="+254700555000",
            password="Stranger@Test1",
            first_name="Other",
            last_name="Landlord",
            role=django_user_model.Role.LANDLORD,
        )
        assert _get(stranger, occupied).status_code == 404
