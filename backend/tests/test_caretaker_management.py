"""Who may take on a caretaker, and who may see them.

Before this existed a caretaker could only be created in Django admin, so the
role was effectively unreachable from the product.
"""
from __future__ import annotations

import pytest
from rest_framework.test import APIClient

from apps.accounts.models import User


def _register(actor, role, phone):
    client = APIClient()
    client.force_authenticate(user=actor)
    return client.post(
        "/api/v1/auth/register/",
        {
            "phone_number": phone,
            "first_name": "New",
            "last_name": "Person",
            "role": role,
            "password": "Caretaker@Test1",
            "password_confirm": "Caretaker@Test1",
        },
        format="json",
    )


class TestCreatingACaretaker:
    def test_a_landlord_can_take_on_a_caretaker(self, landlord):
        assert _register(landlord, "caretaker", "+254700222001").status_code == 201

    def test_the_new_caretaker_has_the_caretaker_role(self, landlord):
        _register(landlord, "caretaker", "+254700222002")
        assert User.objects.get(phone_number="+254700222002").role == User.Role.CARETAKER

    def test_the_caretaker_is_stamped_with_who_hired_them(self, landlord):
        _register(landlord, "caretaker", "+254700222003")
        created = User.objects.get(phone_number="+254700222003")
        assert created.created_by == landlord

    def test_a_caretaker_cannot_hire_another_caretaker(self, caretaker):
        # Otherwise one caretaker could quietly add a peer behind the owner's back.
        assert _register(caretaker, "caretaker", "+254700222004").status_code == 400

    def test_a_caretaker_can_still_add_a_tenant(self, caretaker):
        assert _register(caretaker, "tenant", "+254700222005").status_code == 201

    def test_a_landlord_cannot_create_another_landlord(self, landlord):
        assert _register(landlord, "landlord", "+254700222006").status_code == 400

    def test_a_tenant_cannot_create_anyone(self, tenant):
        assert _register(tenant, "tenant", "+254700222007").status_code == 403


class TestListingCaretakers:
    def test_a_landlord_sees_the_caretaker_they_hired(self, landlord):
        _register(landlord, "caretaker", "+254700222010")
        client = APIClient()
        client.force_authenticate(user=landlord)
        body = client.get("/api/v1/auth/caretakers/").content.decode()
        assert "+254700222010" in body

    def test_a_landlord_does_not_see_another_landlords_caretaker(
        self, landlord, django_user_model
    ):
        stranger = django_user_model.objects.create_user(
            phone_number="+254700333000",
            password="Other@Test1",
            first_name="Other",
            last_name="Landlord",
            role=django_user_model.Role.LANDLORD,
        )
        _register(stranger, "caretaker", "+254700222011")

        client = APIClient()
        client.force_authenticate(user=landlord)
        body = client.get("/api/v1/auth/caretakers/").content.decode()
        assert "+254700222011" not in body

    def test_tenants_are_not_listed_as_caretakers(self, landlord, tenant, tenancy):
        client = APIClient()
        client.force_authenticate(user=landlord)
        body = client.get("/api/v1/auth/caretakers/").content.decode()
        assert tenant.phone_number not in body

    def test_the_caretaker_list_does_not_leak_a_kra_pin(self, landlord):
        _register(landlord, "caretaker", "+254700222012")
        hired = User.objects.get(phone_number="+254700222012")
        hired.kra_pin = "A012345678Z"
        hired.save(update_fields=["kra_pin"])

        client = APIClient()
        client.force_authenticate(user=landlord)
        body = client.get("/api/v1/auth/caretakers/").content.decode()
        assert "A012345678Z" not in body


class TestAssigningACaretaker:
    def test_a_landlord_can_assign_their_caretaker_to_a_property(
        self, landlord, property_
    ):
        _register(landlord, "caretaker", "+254700222020")
        hired = User.objects.get(phone_number="+254700222020")

        client = APIClient()
        client.force_authenticate(user=landlord)
        resp = client.patch(
            f"/api/v1/properties/{property_.id}/",
            {"caretaker": hired.id},
            format="json",
        )
        assert resp.status_code == 200

    def test_a_tenant_cannot_be_assigned_as_caretaker(
        self, landlord, property_, tenant
    ):
        client = APIClient()
        client.force_authenticate(user=landlord)
        resp = client.patch(
            f"/api/v1/properties/{property_.id}/",
            {"caretaker": tenant.id},
            format="json",
        )
        assert resp.status_code == 400
