"""A tenant is texted a receipt when the landlord records their payment."""
from __future__ import annotations

import pytest
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(notification_tasks.send_sms, "delay", lambda recipient_id, message, **k: sent.append((recipient_id, message)))
    return sent


def _record(landlord, invoice, amount, method="cash"):
    api = APIClient()
    api.force_authenticate(user=landlord)
    return api.post("/api/v1/payments/record/", {"invoice": invoice.id, "method": method, "amount": amount}, format="json")


@pytest.mark.django_db
class TestTheReceipt:
    def test_it_goes_to_the_tenant(self, landlord, invoice, texts):
        _record(landlord, invoice, "5000")
        assert texts[0][0] == invoice.tenancy.tenant_id

    def test_it_says_what_was_paid_and_what_is_left(self, landlord, invoice, texts):
        _record(landlord, invoice, "5000")
        left = invoice.amount_due - 5000
        assert texts[0][1] == (
            f"Dear {invoice.tenancy.tenant.first_name}, your cash payment of KES 5,000 for "
            f"{invoice.tenancy.unit.property.name} Unit {invoice.tenancy.unit.unit_number} has been "
            f"received. You still owe KES {left:,.0f} on your {invoice.period_start:%B} bill."
        )

    def test_paying_it_all_says_so(self, landlord, invoice, texts):
        _record(landlord, invoice, str(invoice.amount_due))
        assert texts[0][1].endswith(f"Your {invoice.period_start:%B} bill is fully paid.")

    def test_a_bank_payment_is_called_one(self, landlord, invoice, texts):
        _record(landlord, invoice, "5000", method="bank")
        assert "your bank payment" in texts[0][1]

    def test_a_refused_payment_sends_nothing(self, landlord, invoice, texts):
        _record(landlord, invoice, str(invoice.amount_due + 1))
        assert texts == []
