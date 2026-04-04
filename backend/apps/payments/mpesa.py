"""
M-Pesa Daraja API helper — C2B (Paybill) + STK Push integration.
Handles token caching, C2B URL registration, STK Push initiation, and query.
"""
import base64
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


def _stk_password_and_timestamp() -> tuple[str, str]:
    """
    Generate the STK Push password and timestamp.
    Password = base64(shortcode + passkey + timestamp)
    Timestamp format: yyyyMMddHHmmss
    """
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    raw = f"{settings.MPESA_SHORTCODE}{settings.MPESA_PASSKEY}{timestamp}"
    password = base64.b64encode(raw.encode("utf-8")).decode("utf-8")
    return password, timestamp


def stk_push(phone: str, amount: int, account_ref: str, description: str) -> dict:
    """
    Initiate an STK Push (M-Pesa Express) request.

    Args:
        phone: Customer phone in 2547XXXXXXXX format (no + prefix).
        amount: Amount as integer (no decimals — Daraja rejects floats).
        account_ref: Shown on customer receipt. Max 12 chars.
        description: Transaction description. Keep ≤ 13 chars to be safe.

    Returns:
        Daraja response dict with MerchantRequestID and CheckoutRequestID.
    """
    token = get_access_token()
    password, timestamp = _stk_password_and_timestamp()

    payload = {
        "BusinessShortCode": settings.MPESA_SHORTCODE,
        "Password": password,
        "Timestamp": timestamp,
        "TransactionType": "CustomerPayBillOnline",
        "Amount": int(amount),
        "PartyA": phone,
        "PartyB": settings.MPESA_SHORTCODE,
        "PhoneNumber": phone,
        "CallBackURL": settings.MPESA_STK_CALLBACK_URL,
        "AccountReference": account_ref[:12],
        "TransactionDesc": description[:13],
    }

    resp = requests.post(
        f"{_base_url()}/mpesa/stkpush/v1/processrequest",
        json=payload,
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    logger.info("STK Push initiated: %s", data)
    return data


def stk_query(checkout_request_id: str) -> dict:
    """
    Query the status of a pending STK Push transaction.
    Use for reconciliation when a callback was not received.
    """
    token = get_access_token()
    password, timestamp = _stk_password_and_timestamp()

    payload = {
        "BusinessShortCode": settings.MPESA_SHORTCODE,
        "Password": password,
        "Timestamp": timestamp,
        "CheckoutRequestID": checkout_request_id,
    }

    resp = requests.post(
        f"{_base_url()}/mpesa/stkpushquery/v1/query",
        json=payload,
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    logger.info("STK Query result for %s: %s", checkout_request_id, data)
    return data
