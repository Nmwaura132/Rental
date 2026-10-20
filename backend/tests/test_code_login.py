"""Signing in with a code texted to your phone instead of a password."""
from __future__ import annotations

import re

import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks

User = get_user_model()


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(
        notification_tasks.send_sms,
        "delay",
        lambda recipient_id, message, phone_number=None: sent.append((recipient_id, message)),
    )
    return sent


def _request(phone):
    return APIClient().post("/api/v1/auth/login/request-code/", {"phone_number": phone}, format="json")


def _sign_in(phone, code):
    return APIClient().post("/api/v1/auth/login/code/", {"phone_number": phone, "code": code}, format="json")


def _code(texts):
    return re.search(r"\b(\d{6})\b", texts[-1][1]).group(1)


@pytest.mark.django_db
class TestGettingASignInCode:
    def test_an_account_is_texted_a_code(self, texts, tenant):
        _request(tenant.phone_number)
        assert texts[0][0] == tenant.id

    def test_a_number_with_no_account_is_texted_nothing(self, texts):
        _request("0799000111")
        assert texts == []

    def test_the_reply_does_not_reveal_who_has_an_account(self, texts, tenant):
        assert _request(tenant.phone_number).data == _request("0799000111").data

    def test_a_deactivated_account_gets_no_code(self, texts, tenant):
        tenant.is_active = False
        tenant.save(update_fields=["is_active"])
        _request(tenant.phone_number)
        assert texts == []


@pytest.mark.django_db
class TestSigningInWithTheCode:
    def test_the_right_code_signs_them_in(self, texts, tenant):
        _request(tenant.phone_number)
        assert _sign_in(tenant.phone_number, _code(texts)).status_code == 200

    def test_it_says_who_they_are(self, texts, tenant):
        _request(tenant.phone_number)
        assert _sign_in(tenant.phone_number, _code(texts)).data["role"] == "tenant"

    def test_the_session_works(self, texts, landlord):
        _request(landlord.phone_number)
        access = _sign_in(landlord.phone_number, _code(texts)).data["access"]
        api = APIClient()
        api.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        assert api.get("/api/v1/auth/profile/").status_code == 200

    def test_the_local_number_works_too(self, texts, tenant):
        _request("0700111111")
        assert _sign_in("0700111111", _code(texts)).status_code == 200

    def test_a_wrong_code_is_refused(self, texts, tenant):
        _request(tenant.phone_number)
        assert _sign_in(tenant.phone_number, "000000").status_code == 400

    def test_a_code_signs_in_once(self, texts, tenant):
        _request(tenant.phone_number)
        code = _code(texts)
        _sign_in(tenant.phone_number, code)
        assert _sign_in(tenant.phone_number, code).status_code == 400

    def test_five_wrong_guesses_burn_the_code(self, texts, tenant, monkeypatch):
        from apps.core.throttles import RegisterThrottle

        monkeypatch.setattr(RegisterThrottle, "rate", "100/minute")
        _request(tenant.phone_number)
        code = _code(texts)
        for _ in range(5):
            _sign_in(tenant.phone_number, "000000")
        assert _sign_in(tenant.phone_number, code).status_code == 400

    def test_a_sign_up_code_does_not_sign_in(self, texts, tenant):
        # Same number, different purpose: the salt keeps them apart.
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000222"}, format="json")
        signup_code = _code(texts)
        assert _sign_in("0799000222", signup_code).status_code == 400

    def test_the_password_still_works_as_a_backup(self, tenant):
        response = APIClient().post(
            "/api/v1/auth/login/",
            {"phone_number": tenant.phone_number, "password": "Tenant@Test1"},
            format="json",
        )
        assert response.status_code == 200


@pytest.mark.django_db
class TestAccountsWithoutAPassword:
    def test_a_landlord_can_sign_up_without_one(self, texts):
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000333"}, format="json")
        response = APIClient().post(
            "/api/v1/auth/signup/",
            {"phone_number": "0799000333", "code": _code(texts), "first_name": "Achieng", "last_name": "Otieno"},
            format="json",
        )
        assert response.status_code == 201

    def test_that_account_has_no_password_to_guess(self, texts):
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000333"}, format="json")
        APIClient().post(
            "/api/v1/auth/signup/",
            {"phone_number": "0799000333", "code": _code(texts), "first_name": "Achieng", "last_name": "Otieno"},
            format="json",
        )
        assert not User.objects.get(phone_number="+254799000333").has_usable_password()

    def test_a_landlord_can_add_a_tenant_without_inventing_a_password(self, landlord):
        api = APIClient()
        api.force_authenticate(user=landlord)
        response = api.post(
            "/api/v1/auth/register/",
            {"phone_number": "0799000444", "first_name": "Juma", "last_name": "Mwangi", "role": "tenant"},
            format="json",
        )
        assert response.status_code == 201

    def test_that_tenant_signs_in_with_a_code(self, landlord, texts):
        api = APIClient()
        api.force_authenticate(user=landlord)
        api.post(
            "/api/v1/auth/register/",
            {"phone_number": "0799000444", "first_name": "Juma", "last_name": "Mwangi", "role": "tenant"},
            format="json",
        )
        _request("0799000444")
        assert _sign_in("0799000444", _code(texts)).status_code == 200
