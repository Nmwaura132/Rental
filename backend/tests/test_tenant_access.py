"""While the app is closed to tenants, they get SMS but cannot sign in."""
from __future__ import annotations

import re

import pytest
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks

CLOSED = "The Kasa app is not open to tenants yet."


@pytest.fixture(autouse=True)
def app_closed(settings):
    settings.TENANT_APP_ACCESS = False


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(
        notification_tasks.send_sms,
        "delay",
        lambda recipient_id, message, phone_number=None: sent.append(message),
    )
    return sent


def _post(path, body):
    return APIClient().post(path, body, format="json")


@pytest.mark.django_db
class TestATenantCannotSignIn:
    def test_with_their_password(self, tenant):
        response = _post("/api/v1/auth/login/", {"phone_number": tenant.phone_number, "password": "Tenant@Test1"})
        assert response.status_code == 403

    def test_and_is_told_why(self, tenant):
        response = _post("/api/v1/auth/login/", {"phone_number": tenant.phone_number, "password": "Tenant@Test1"})
        assert CLOSED in str(response.data["detail"])

    def test_is_sent_no_sign_in_code(self, tenant, texts):
        _post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number})
        assert not re.search(r"\b\d{6}\b", texts[0])

    def test_is_texted_that_the_app_is_not_open(self, tenant, texts):
        _post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number})
        assert CLOSED in texts[0]

    def test_the_reply_does_not_reveal_they_are_a_tenant(self, tenant, landlord, texts):
        as_tenant = _post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number}).data
        as_landlord = _post("/api/v1/auth/login/request-code/", {"phone_number": landlord.phone_number}).data
        assert as_tenant == as_landlord

    def test_is_sent_no_password_reset_code(self, tenant, texts):
        _post("/api/v1/auth/password-reset/request/", {"phone_number": tenant.phone_number})
        assert not re.search(r"\b\d{6}\b", texts[0])

    def test_trying_to_sign_up_says_the_app_is_not_open(self, tenant, texts):
        _post("/api/v1/auth/signup/request-code/", {"phone_number": tenant.phone_number})
        assert CLOSED in texts[0]


@pytest.mark.django_db
class TestOthersStillCan:
    def test_a_landlord_signs_in(self, landlord):
        response = _post(
            "/api/v1/auth/login/", {"phone_number": landlord.phone_number, "password": "Landlord@Test1"}
        )
        assert response.status_code == 200

    def test_a_landlord_gets_a_code(self, landlord, texts):
        _post("/api/v1/auth/login/request-code/", {"phone_number": landlord.phone_number})
        assert re.search(r"\b\d{6}\b", texts[0])


@pytest.mark.django_db
def test_opening_the_app_lets_tenants_in(tenant, settings):
    settings.TENANT_APP_ACCESS = True
    response = _post("/api/v1/auth/login/", {"phone_number": tenant.phone_number, "password": "Tenant@Test1"})
    assert response.status_code == 200
