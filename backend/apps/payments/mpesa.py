"""
M-Pesa Daraja API helper — C2B (Paybill) integration.
Handles token caching, C2B URL registration, and webhook processing.
"""
import hashlib
import logging
from datetime import datetime

import requests
from django.conf import settings
from django.core.cache import cache

logger = logging.getLogger(__name__)

DARAJA_BASE = {
    "sandbox": "https://sandbox.safaricom.co.ke",
    "production": "https://api.safaricom.co.ke",
}


def _base_url() -> str:
    return DARAJA_BASE[settings.MPESA_ENVIRONMENT]


def get_access_token() -> str:
    """Fetch and cache an OAuth access token (valid 1 hour)."""
    cached = cache.get("mpesa_access_token")
    if cached:
        return cached

    resp = requests.get(
        f"{_base_url()}/oauth/v1/generate?grant_type=client_credentials",
        auth=(settings.MPESA_CONSUMER_KEY, settings.MPESA_CONSUMER_SECRET),
        timeout=10,
    )
    resp.raise_for_status()
    token = resp.json()["access_token"]
    cache.set("mpesa_access_token", token, timeout=3500)  # expire slightly before 1h
    return token


def register_c2b_urls() -> dict:
    """
    Register Validation and Confirmation callback URLs with Daraja.
    Should be called once at deployment or on demand.
    """
    token = get_access_token()
    payload = {
        "ShortCode": settings.MPESA_SHORTCODE,
        "ResponseType": "Completed",
        "ConfirmationURL": f"{settings.MPESA_CALLBACK_URL}confirm/",
        "ValidationURL": f"{settings.MPESA_CALLBACK_URL}validate/",
    }
    resp = requests.post(
        f"{_base_url()}/mpesa/c2b/v1/registerurl",
        json=payload,
        headers={"Authorization": f"Bearer {token}"},
        timeout=10,
    )
    resp.raise_for_status()
    logger.info("M-Pesa C2B URLs registered: %s", resp.json())
    return resp.json()


def make_idempotency_key(receipt_number: str) -> str:
    """Generate a stable idempotency key from M-Pesa receipt number."""
    return hashlib.sha256(f"mpesa:{receipt_number}".encode()).hexdigest()[:60]
