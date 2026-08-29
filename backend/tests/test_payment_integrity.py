"""Guards on money that a person, rather than a gateway, can move.

Confirmed payments are immutable and cannot be deleted, so anything wrong that
gets in stays in. These cover the three ways a bad figure could previously be
recorded permanently.
"""
from __future__ import annotations

from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.models import BankPaymentNotification, Payment
from apps.payments.services import apply_confirmed_payment
from apps.payments.tasks import poll_equity_statement


def _record(user, invoice, amount, method="cash"):
    client = APIClient()
    client.force_authenticate(user=user)
    return client.post(
        "/api/v1/payments/record/",
        {"invoice": invoice.id, "method": method, "amount": str(amount)},
        format="json",
    )


class TestWhoRecordedIt:
    def test_a_hand_entered_payment_records_who_entered_it(
        self, landlord, invoice, tenancy
    ):
        # Without this the record said money arrived but not who said so, and
        # the row can never be edited or removed.
        _record(landlord, invoice, "5000.00")
        assert Payment.objects.get().recorded_by == landlord

    def test_a_gateway_payment_has_no_recorder(self, invoice, tenancy):
        # Nobody typed it, so attributing it to a person would be a lie.
        payment, _ = apply_confirmed_payment(
            invoice_id=invoice.id,
            method=Payment.Method.MPESA,
            amount=Decimal("5000.00"),
            idempotency_key="mpesa:integrity-1",
            paid_at=timezone.now(),
        )
        assert payment.recorded_by is None


class TestHandEnteredOverpayment:
    def test_more_than_the_balance_is_refused(self, landlord, invoice, tenancy):
        assert _record(landlord, invoice, "999999.00").status_code == 400

    def test_the_refusal_states_the_actual_balance(self, landlord, invoice, tenancy):
        body = _record(landlord, invoice, "999999.00").json()["error"]
        assert "15,000.00" in body

    def test_nothing_is_recorded_when_refused(self, landlord, invoice, tenancy):
        _record(landlord, invoice, "999999.00")
        assert Payment.objects.count() == 0

    def test_paying_the_exact_balance_is_allowed(self, landlord, invoice, tenancy):
        assert _record(landlord, invoice, "15000.00").status_code == 201

    def test_a_part_payment_is_allowed(self, landlord, invoice, tenancy):
        assert _record(landlord, invoice, "5000.00").status_code == 201

    def test_the_remaining_balance_is_what_is_left(self, landlord, invoice, tenancy):
        _record(landlord, invoice, "5000.00")
        assert _record(landlord, invoice, "10000.01").status_code == 400


class TestGatewayOverpaymentIsKept:
    def test_an_mpesa_overpayment_is_still_recorded(self, invoice, tenancy):
        # The money has already moved; refusing it would lose a real receipt.
        payment, _ = apply_confirmed_payment(
            invoice_id=invoice.id,
            method=Payment.Method.MPESA,
            amount=Decimal("20000.00"),
            idempotency_key="mpesa:over-1",
            paid_at=timezone.now(),
        )
        assert payment.amount == Decimal("20000.00")


class TestBankStatementAmounts:
    @pytest.fixture(autouse=True)
    def _stub_jenga(self, monkeypatch):
        """Feeds statement rows in without touching the Jenga API.

        A stub module rather than patching the real one: apps.payments.jenga
        imports `cryptography`, which this environment does not have because the
        bank integration is dormant, so importing it at all would fail.
        """
        import sys, types

        self.rows = []
        stub = types.ModuleType("apps.payments.jenga")
        stub.get_mini_statement = lambda: self.rows
        stub.get_full_statement = lambda a, b: self.rows
        monkeypatch.setitem(sys.modules, "apps.payments.jenga", stub)

    def test_a_row_with_no_amount_is_skipped(self, db):
        # It used to fall back to runningBalance — the account balance after the
        # transaction — and record that as the payment.
        self.rows = [
            {"transactionReference": "EQ-NO-AMT", "runningBalance": "874500.00",
             "narrative": "RENT", "date": "2026-08-01"}
        ]
        poll_equity_statement()
        assert not BankPaymentNotification.objects.filter(
            transaction_ref="EQ-NO-AMT"
        ).exists()

    def test_a_row_with_an_amount_is_recorded(self, db):
        self.rows = [
            {"transactionReference": "EQ-OK", "amount": "15000.00",
             "narrative": "RENT 101", "date": "2026-08-01"}
        ]
        poll_equity_statement()
        assert BankPaymentNotification.objects.get(
            transaction_ref="EQ-OK"
        ).amount == Decimal("15000.00")

    def test_a_zero_amount_row_is_skipped(self, db):
        self.rows = [
            {"transactionReference": "EQ-ZERO", "amount": "0",
             "narrative": "REVERSAL", "date": "2026-08-01"}
        ]
        poll_equity_statement()
        assert not BankPaymentNotification.objects.filter(
            transaction_ref="EQ-ZERO"
        ).exists()
