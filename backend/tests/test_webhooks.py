"""Webhook auth contract: KCB IPN must fail-CLOSED in production when the
secret isn't configured. The pre-fix code returned True (accepted any payload).
"""
from __future__ import annotations

from unittest.mock import patch

import pytest

from apps.payments.bank_views import EquityIPNView


@pytest.mark.django_db
def test_equity_basic_auth_fails_closed_when_creds_missing_in_prod():
    view = EquityIPNView()
    with patch("apps.payments.bank_views.settings") as mock_settings:
        mock_settings.DEBUG = False
        mock_settings.JENGA_IPN_USERNAME = ""
        mock_settings.JENGA_IPN_PASSWORD = ""
        request = type("R", (), {"headers": {}})()
        assert view._verify_basic_auth(request) is False
