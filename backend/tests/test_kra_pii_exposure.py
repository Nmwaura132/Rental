"""Who may read the identifiers collected for KRA filing.

A national ID and a KRA PIN together are the pair used for SIM-swap and
identity fraud in Kenya, so these guard the read paths rather than the writes.
"""
from __future__ import annotations

import pytest
from rest_framework.test import APIClient


@pytest.fixture
def tenant_with_pii(tenant):
    tenant.national_id = "12345678"
    tenant.kra_pin = "A012345678Z"
    tenant.save(update_fields=["national_id", "kra_pin"])
    return tenant


def _list_tenants(user):
    client = APIClient()
    client.force_authenticate(user=user)
    return client.get("/api/v1/auth/tenants/")


class TestTenantPicker:
    def test_a_caretaker_cannot_read_a_tenants_kra_pin(
        self, tenant_with_pii, caretaker, property_, unit, tenancy
    ):
        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        body = _list_tenants(caretaker).content.decode()
        assert "A012345678Z" not in body

    def test_a_caretaker_cannot_read_a_tenants_national_id(
        self, tenant_with_pii, caretaker, property_, unit, tenancy
    ):
        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        body = _list_tenants(caretaker).content.decode()
        assert "12345678" not in body

    def test_a_landlord_cannot_read_a_tenants_kra_pin_from_the_picker(
        self, tenant_with_pii, landlord, tenancy
    ):
        # The picker exists to choose a tenant; the PIN belongs in the MRI
        # statement, which is scoped and purpose-built.
        body = _list_tenants(landlord).content.decode()
        assert "A012345678Z" not in body

    def test_the_picker_still_returns_the_tenants_name(
        self, tenant_with_pii, landlord, tenancy
    ):
        body = _list_tenants(landlord).content.decode()
        assert "Test" in body


class TestPropertyLrNumber:
    def test_a_tenant_cannot_read_the_landlords_lr_number(
        self, tenant, landlord, property_, unit, tenancy
    ):
        property_.lr_number = "LR 209/12345"
        property_.save(update_fields=["lr_number"])
        client = APIClient()
        client.force_authenticate(user=tenant)
        assert "LR 209/12345" not in client.get("/api/v1/properties/").content.decode()

    def test_the_owner_can_still_read_their_own_lr_number(
        self, landlord, property_, unit
    ):
        property_.lr_number = "LR 209/12345"
        property_.save(update_fields=["lr_number"])
        client = APIClient()
        client.force_authenticate(user=landlord)
        assert "LR 209/12345" in client.get("/api/v1/properties/").content.decode()


class TestMriInputBounds:
    @pytest.mark.parametrize("year", ["0", "1", "9999", "-1"])
    def test_an_out_of_range_year_is_rejected_not_crashed(self, landlord, year):
        # date() raises for year 0 or 10000; an uncaught ValueError here is a
        # 500 that renders Django's debug page on a DEBUG staging host.
        client = APIClient()
        client.force_authenticate(user=landlord)
        resp = client.get(f"/api/v1/payments/mri/?year={year}&month=1")
        assert resp.status_code == 400

    def test_a_non_numeric_year_is_rejected(self, landlord):
        client = APIClient()
        client.force_authenticate(user=landlord)
        assert client.get("/api/v1/payments/mri/?year=abc").status_code == 400

    def test_a_tenant_cannot_read_an_mri_statement(self, tenant):
        client = APIClient()
        client.force_authenticate(user=tenant)
        assert client.get("/api/v1/payments/mri/").status_code == 403


class TestPinNormalization:
    def test_a_lowercase_pin_is_stored_upper_cased(self, tenant):
        # Stored as typed, it would be emitted verbatim into the KRA rent roll.
        tenant.kra_pin = "a012345678z"
        tenant.save()
        tenant.refresh_from_db()
        assert tenant.kra_pin == "A012345678Z"
