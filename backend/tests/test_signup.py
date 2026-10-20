"""A landlord signing themselves up with their phone number."""
from __future__ import annotations

import re

import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks

User = get_user_model()

NEW_NUMBER = "0712345678"
NEW_E164 = "+254712345678"


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(
        notification_tasks.send_sms,
        "delay",
        lambda recipient_id, message, phone_number=None: sent.append((recipient_id, message, phone_number)),
    )
    return sent


def _request_code(phone=NEW_NUMBER):
    return APIClient().post("/api/v1/auth/signup/request-code/", {"phone_number": phone}, format="json")


def _code_from(texts):
    return re.search(r"\b(\d{6})\b", texts[-1][1]).group(1)


def _sign_up(code, **overrides):
    body = {
        "phone_number": NEW_NUMBER,
        "code": code,
        "first_name": "Wanjiru",
        "last_name": "Kamau",
        "password": "Strong-Pass-2026",
        **overrides,
    }
    return APIClient().post("/api/v1/auth/signup/", body, format="json")


@pytest.mark.django_db
class TestGettingACode:
    def test_a_new_number_is_texted_a_code(self, texts):
        _request_code()
        assert re.search(r"\b\d{6}\b", texts[0][1])

    def test_the_code_goes_to_the_number_typed(self, texts):
        _request_code()
        assert texts[0][2] == NEW_E164

    def test_a_number_with_an_account_is_told_to_sign_in(self, texts, landlord):
        _request_code(landlord.phone_number)
        assert "already has a Kasa account" in texts[0][1]

    def test_a_number_with_an_account_gets_no_code(self, texts, landlord):
        _request_code(landlord.phone_number)
        assert not re.search(r"\b\d{6}\b", texts[0][1])

    def test_the_reply_does_not_reveal_who_has_an_account(self, texts, landlord):
        assert _request_code(landlord.phone_number).data == _request_code().data

    def test_a_number_that_is_not_kenyan_is_refused(self, texts):
        assert _request_code("12").status_code == 400


@pytest.mark.django_db
class TestSigningUp:
    def test_the_right_code_creates_the_account(self, texts):
        _request_code()
        assert _sign_up(_code_from(texts)).status_code == 201

    def test_the_account_is_a_landlord(self, texts):
        _request_code()
        _sign_up(_code_from(texts))
        assert User.objects.get(phone_number=NEW_E164).role == User.Role.LANDLORD

    def test_they_are_signed_in_straight_away(self, texts):
        _request_code()
        response = _sign_up(_code_from(texts))
        me = APIClient()
        me.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
        assert me.get("/api/v1/auth/profile/").status_code == 200

    def test_the_password_they_chose_works(self, texts):
        _request_code()
        _sign_up(_code_from(texts))
        login = APIClient().post(
            "/api/v1/auth/login/",
            {"phone_number": NEW_NUMBER, "password": "Strong-Pass-2026"},
            format="json",
        )
        assert login.status_code == 200


@pytest.mark.django_db
class TestWhatIsRefused:
    def test_a_wrong_code(self, texts):
        _request_code()
        assert _sign_up("000000").status_code == 400

    def test_a_wrong_code_creates_nothing(self, texts):
        _request_code()
        _sign_up("000000")
        assert not User.objects.filter(phone_number=NEW_E164).exists()

    def test_a_code_is_used_once(self, texts):
        _request_code()
        code = _code_from(texts)
        _sign_up(code)
        assert _sign_up(code).status_code == 400

    def test_five_wrong_guesses_burn_the_code(self, texts, monkeypatch):
        # The per-IP limit would also stop a sixth try; lift it to show the
        # code itself is gone, for an attacker spread across many IPs.
        from apps.core.throttles import RegisterThrottle

        monkeypatch.setattr(RegisterThrottle, "rate", "100/minute")
        _request_code()
        code = _code_from(texts)
        for _ in range(5):
            _sign_up("000000")
        assert _sign_up(code).status_code == 400

    def test_a_weak_password(self, texts):
        _request_code()
        assert _sign_up(_code_from(texts), password="123").status_code == 400

    def test_a_weak_password_leaves_the_code_usable(self, texts):
        _request_code()
        code = _code_from(texts)
        _sign_up(code, password="123")
        assert _sign_up(code).status_code == 201

    def test_a_missing_name(self, texts):
        _request_code()
        assert _sign_up(_code_from(texts), first_name="").status_code == 400

    def test_a_password_reset_code_does_not_sign_up(self, texts, landlord):
        # Different salt: a reset code for one number is not a sign-up code.
        APIClient().post(
            "/api/v1/auth/password-reset/request/", {"phone_number": landlord.phone_number}, format="json"
        )
        reset_code = _code_from(texts)
        response = _sign_up(reset_code, phone_number=landlord.phone_number)
        assert response.status_code == 400


@pytest.mark.django_db
class TestTextingSomeoneWithNoAccount:
    def test_the_sms_goes_out_without_a_user(self, monkeypatch, settings):
        settings.MOBILESASA_API_KEY = "key"
        sent = {}

        class _Reply:
            status_code = 200
            ok = True

            def json(self):
                return {"status": True, "messageId": "m1"}

        def post(url, json, headers, timeout):
            sent.update(json)
            return _Reply()

        monkeypatch.setattr(notification_tasks._requests, "post", post)
        notification_tasks.send_sms.apply(args=[None, "code 123456"], kwargs={"phone_number": NEW_E164})
        assert sent["phone"] == NEW_E164
