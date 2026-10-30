"""A landlord deleting a tenant they entered, and everything kept about them."""
from __future__ import annotations

from decimal import Decimal

import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.models import Invoice, Payment
from apps.properties.models import Unit
from apps.tenants.models import MaintenanceRequest, Tenancy

User = get_user_model()


def _as(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


def _url(tenant):
    return f"/api/v1/auth/tenants/{tenant.id}/"


def _pay(invoice, amount, method=Payment.Method.CASH, by=None):
    return Payment.objects.create(
        invoice=invoice, amount=Decimal(amount), method=method, status=Payment.Status.CONFIRMED,
        recorded_by=by, paid_at=timezone.now(), idempotency_key=f"{method}:{amount}:{invoice.pk}:{by and by.pk}",
    )


@pytest.fixture
def other_landlord(db):
    return User.objects.create_user(
        phone_number="+254700999003", password="Other@Test1", first_name="O", last_name="L",
        role=User.Role.LANDLORD,
    )


@pytest.mark.django_db
class TestBeforeDeleting:
    def test_the_landlord_is_shown_what_goes(self, landlord, tenant, invoice):
        _pay(invoice, "5000", by=landlord)
        found = _as(landlord).get(_url(tenant)).data
        assert (found["bills"], found["payments"], found["paid"]) == (1, 1, Decimal("5000"))

    def test_it_names_the_house(self, landlord, tenant, tenancy):
        assert _as(landlord).get(_url(tenant)).data["houses"] == [tenancy.unit.unit_number]


@pytest.mark.django_db
class TestDeleting:
    def test_the_tenant_is_gone(self, landlord, tenant, tenancy):
        _as(landlord).delete(_url(tenant))
        assert not User.objects.filter(pk=tenant.pk).exists()

    def test_their_bills_and_hand_recorded_payments_go_too(self, landlord, tenant, invoice):
        _pay(invoice, "5000", by=landlord)
        _as(landlord).delete(_url(tenant))
        assert (Invoice.objects.count(), Payment.objects.count()) == (0, 0)

    def test_their_repairs_go_too(self, landlord, tenant, tenancy):
        MaintenanceRequest.objects.create(tenancy=tenancy, title="Leak", description="")
        _as(landlord).delete(_url(tenant))
        assert not MaintenanceRequest.objects.exists()

    def test_the_house_is_vacant_again(self, landlord, tenant, tenancy):
        _as(landlord).delete(_url(tenant))
        assert Unit.objects.get(pk=tenancy.unit_id).status == Unit.Status.VACANT

    def test_it_answers_with_no_content(self, landlord, tenant, tenancy):
        assert _as(landlord).delete(_url(tenant)).status_code == 204


@pytest.mark.django_db
class TestWhatCannotBeDeleted:
    def test_a_tenant_with_an_mpesa_payment(self, landlord, tenant, invoice):
        _pay(invoice, "5000", method=Payment.Method.MPESA)
        assert _as(landlord).delete(_url(tenant)).status_code == 400

    def test_who_then_stays(self, landlord, tenant, invoice):
        _pay(invoice, "5000", method=Payment.Method.MPESA)
        _as(landlord).delete(_url(tenant))
        assert Tenancy.objects.filter(tenant=tenant).exists()

    def test_the_preview_says_why(self, landlord, tenant, invoice):
        _pay(invoice, "5000", method=Payment.Method.MPESA)
        assert _as(landlord).get(_url(tenant)).data["can_delete"] is False

    def test_another_landlords_tenant(self, other_landlord, tenant, tenancy):
        assert _as(other_landlord).delete(_url(tenant)).status_code == 404

    def test_a_landlord_cannot_be_deleted_this_way(self, landlord, other_landlord):
        assert _as(landlord).delete(_url(other_landlord)).status_code == 404

    def test_a_tenant_cannot_delete(self, tenant, tenancy):
        assert _as(tenant).delete(_url(tenant)).status_code == 403

    def test_a_caretaker_cannot_delete(self, caretaker, tenant, tenancy):
        assert _as(caretaker).delete(_url(tenant)).status_code == 403
