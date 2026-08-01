from django.core.cache import cache
from django.utils.crypto import salted_hmac
from rest_framework.test import APIClient


def _otp_digest(phone_number, otp):
    return salted_hmac(
        "kasa.password-reset",
        f"{phone_number}:{otp}",
    ).hexdigest()


def test_password_reset_otp_can_only_be_consumed_once(db, landlord):
    otp = "123456"
    cache.set(
        f"pwd_reset_otp:{landlord.phone_number}",
        _otp_digest(landlord.phone_number, otp),
        timeout=300,
    )
    payload = {
        "phone_number": landlord.phone_number,
        "otp": otp,
        "new_password": "RotatedLandlord@Test2",
    }
    client = APIClient()

    first = client.post("/api/v1/auth/password-reset/", payload, format="json")
    second = client.post("/api/v1/auth/password-reset/", payload, format="json")

    assert first.status_code == 200
    assert second.status_code == 400
