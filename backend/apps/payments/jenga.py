"""
Equity Bank Jenga API client.

Handles:
  - OAuth2 token fetch (username = API key, password = API secret)
  - RSA-SHA256 request signing  (required for account-services endpoints)
  - Account mini-statement fetch (last 10 txns)
  - Account full-statement fetch (date range)

Credentials are read from Django settings:
  JENGA_API_KEY        – Jenga merchant code / username
  JENGA_API_SECRET     – Jenga API secret / password
  JENGA_PRIVATE_KEY    – PEM-encoded RSA private key (for request signing)
  JENGA_ACCOUNT_NUMBER – Equity account to monitor
  JENGA_BASE_URL       – defaults to sandbox: "https://uat.jengahq.io"
  JENGA_COUNTRY_CODE   – defaults to "KE"
  JENGA_CURRENCY_CODE  – defaults to "KES"
"""
import base64
import hashlib
import hmac
import logging
from datetime import datetime, timezone

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

logger = logging.getLogger(__name__)

_token_cache: dict = {}  # {"token": str, "expires_at": float}


def _settings():
    from django.conf import settings
    return settings


def _base_url() -> str:
    return getattr(_settings(), "JENGA_BASE_URL", "https://uat.jengahq.io").rstrip("/")


def _get_token() -> str:
    """Fetch (or return cached) OAuth2 bearer token."""
    import time
    now = time.time()
    if _token_cache.get("token") and _token_cache.get("expires_at", 0) > now + 30:
        return _token_cache["token"]

    s = _settings()
    api_key = getattr(s, "JENGA_API_KEY", "")
    api_secret = getattr(s, "JENGA_API_SECRET", "")
    if not api_key or not api_secret:
        raise ValueError("JENGA_API_KEY and JENGA_API_SECRET must be set in settings.")

    credentials = base64.b64encode(f"{api_key}:{api_secret}".encode()).decode()
    resp = requests.post(
        f"{_base_url()}/identity/v2/token",
        headers={
            "Authorization": f"Basic {credentials}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        data={"grant_type": "client_credentials"},
        timeout=15,
    )
    resp.raise_for_status()
    data = resp.json()
    token = data["access_token"]
    expires_in = int(data.get("expires_in", 3600))

    _token_cache["token"] = token
    _token_cache["expires_at"] = now + expires_in
    return token


def _sign(payload: str) -> str:
    """
    RSA-SHA256 sign *payload* with JENGA_PRIVATE_KEY.
    Returns base64-encoded signature.
    """
    s = _settings()
    pem = getattr(s, "JENGA_PRIVATE_KEY", "")
    if not pem:
        raise ValueError("JENGA_PRIVATE_KEY must be set in settings.")

    private_key = serialization.load_pem_private_key(pem.encode(), password=None)
    sig_bytes = private_key.sign(payload.encode(), padding.PKCS1v15(), hashes.SHA256())
    return base64.b64encode(sig_bytes).decode()


def _headers(signature_payload: str) -> dict:
    return {
        "Authorization": f"Bearer {_get_token()}",
        "signature": _sign(signature_payload),
        "Content-Type": "application/json",
    }


def get_mini_statement() -> list[dict]:
    """
    Fetch the last 10 transactions on the configured Equity account.
    Returns a list of transaction dicts.
    """
    s = _settings()
    account = getattr(s, "JENGA_ACCOUNT_NUMBER", "")
    country = getattr(s, "JENGA_COUNTRY_CODE", "KE")
    currency = getattr(s, "JENGA_CURRENCY_CODE", "KES")

    if not account:
        raise ValueError("JENGA_ACCOUNT_NUMBER must be set in settings.")

    sig_payload = f"{country}{account}"
    resp = requests.get(
        f"{_base_url()}/account/v2/accounts/ministatement",
        headers=_headers(sig_payload),
        params={"countryCode": country, "accountNumber": account},
        timeout=20,
    )
    resp.raise_for_status()
    data = resp.json()
    return data.get("transactions", data.get("data", []))


def get_full_statement(date_from: str, date_to: str) -> list[dict]:
    """
    Fetch transactions between *date_from* and *date_to* (YYYY-MM-DD).
    Returns a list of transaction dicts.
    """
    s = _settings()
    account = getattr(s, "JENGA_ACCOUNT_NUMBER", "")
    country = getattr(s, "JENGA_COUNTRY_CODE", "KE")
    currency = getattr(s, "JENGA_CURRENCY_CODE", "KES")

    if not account:
        raise ValueError("JENGA_ACCOUNT_NUMBER must be set in settings.")

    sig_payload = f"{country}{account}"
    resp = requests.post(
        f"{_base_url()}/account/v2/accounts/fullstatement",
        headers=_headers(sig_payload),
        json={
            "countryCode": country,
            "accountNumber": account,
            "fromDate": date_from,
            "toDate": date_to,
            "limit": 100,
        },
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    return data.get("transactions", data.get("data", []))
