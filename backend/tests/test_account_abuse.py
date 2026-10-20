"""Attempts to get a second account, a different role, or someone else's
account through the code endpoints, and to flood a number with codes."""
from __future__ import annotations

import re

import pytest
from django.contrib.auth import get_user_model
from django.core.cache import cache
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks

User = get_user_model()


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(
        notification_tasks.send_sms,
        "delay",
        lambda recipient_id, message, phone_number=None: sent.append((recipient_id, message, phone_number)),
    )
    return sent


def _code(texts):
    return re.search(r"\b(\d{6})\b", texts[-1][1]).group(1)


def _as(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


@pytest.mark.django_db
class TestOnePersonOneAccount:
    def test_a_signed_in_user_cannot_ask_for_a_sign_up_code(self, texts, landlord):
        response = _as(landlord).post(
            "/api/v1/auth/signup/request-code/", {"phone_number": "0799000555"}, format="json"
        )
        assert response.status_code == 403

    def test_nor_is_a_code_texted_for_them(self, texts, landlord):
        _as(landlord).post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000555"}, format="json")
        assert texts == []

    def test_a_signed_in_user_cannot_complete_a_sign_up(self, texts, landlord):
        # Even holding a valid code obtained while signed out.
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000555"}, format="json")
        response = _as(landlord).post(
            "/api/v1/auth/signup/",
            {"phone_number": "0799000555", "code": _code(texts), "first_name": "A", "last_name": "B"},
            format="json",
        )
        assert response.status_code == 403

    def test_and_no_second_account_exists(self, texts, landlord):
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000555"}, format="json")
        _as(landlord).post(
            "/api/v1/auth/signup/",
            {"phone_number": "0799000555", "code": _code(texts), "first_name": "A", "last_name": "B"},
            format="json",
        )
        assert not User.objects.filter(phone_number="+254799000555").exists()

    def test_a_tenants_number_cannot_sign_up_as_a_landlord(self, texts, tenant):
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": tenant.phone_number}, format="json")
        assert not re.search(r"\b\d{6}\b", texts[-1][1])

    def test_the_tenant_stays_a_tenant(self, texts, tenant):
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": tenant.phone_number}, format="json")
        tenant.refresh_from_db()
        assert tenant.role == User.Role.TENANT


@pytest.mark.django_db
class TestNoChoosingYourOwnRole:
    def test_sign_up_always_makes_a_landlord(self, texts):
        APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000666"}, format="json")
        APIClient().post(
            "/api/v1/auth/signup/",
            {
                "phone_number": "0799000666",
                "code": _code(texts),
                "first_name": "A",
                "last_name": "B",
                "role": "admin",
                "is_staff": True,
                "is_superuser": True,
            },
            format="json",
        )
        user = User.objects.get(phone_number="+254799000666")
        assert (user.role, user.is_staff, user.is_superuser) == (User.Role.LANDLORD, False, False)


@pytest.mark.django_db
class TestFloodingANumber:
    def test_a_second_code_within_a_minute_is_not_sent(self, texts, tenant):
        api = APIClient()
        api.post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number}, format="json")
        api.post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number}, format="json")
        assert len(texts) == 1

    def test_the_first_code_still_works_after(self, texts, tenant):
        api = APIClient()
        api.post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number}, format="json")
        code = _code(texts)
        api.post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number}, format="json")
        response = api.post(
            "/api/v1/auth/login/code/", {"phone_number": tenant.phone_number, "code": code}, format="json"
        )
        assert response.status_code == 200

    def test_no_more_than_five_an_hour(self, texts, tenant, monkeypatch):
        from apps.core.throttles import SignupCodeThrottle

        # Lift the per-IP limit to show the per-number one, as an attacker
        # rotating IPs would.
        monkeypatch.setattr(SignupCodeThrottle, "rate", "100/minute")
        for _ in range(7):
            cache.delete(f"login_cooldown:{tenant.phone_number}")
            APIClient().post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number}, format="json")
        assert len(texts) == 5

    def test_the_limit_does_not_reveal_who_has_an_account(self, texts, tenant):
        api = APIClient()
        api.post("/api/v1/auth/signup/request-code/", {"phone_number": tenant.phone_number}, format="json")
        limited = api.post("/api/v1/auth/signup/request-code/", {"phone_number": tenant.phone_number}, format="json")
        fresh = api.post("/api/v1/auth/signup/request-code/", {"phone_number": "0799000777"}, format="json")
        assert limited.data == fresh.data

    def test_one_purpose_does_not_use_up_another(self, texts, tenant):
        # Asking for a sign-in code must not block a password-reset code.
        api = APIClient()
        api.post("/api/v1/auth/login/request-code/", {"phone_number": tenant.phone_number}, format="json")
        api.post("/api/v1/auth/password-reset/request/", {"phone_number": tenant.phone_number}, format="json")
        assert len(texts) == 2
