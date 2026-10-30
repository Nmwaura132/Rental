"""A tenant is texted a receipt when the landlord records their payment, and an
M-Pesa payment confirmed by hand is kept as M-Pesa, under its code."""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks
from apps.payments.models import Invoice, Payment, TenancyCredit


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(notification_tasks.send_sms, "delay", lambda recipient_id, message, **k: sent.append((recipient_id, message)))
    return sent


@pytest.fixture
def next_bill(invoice):
    return Invoice.objects.create(
        tenancy=invoice.tenancy,
        invoice_number="INV-NEXT",
        period_start=invoice.period_end + timedelta(days=1),
        period_end=invoice.period_end + timedelta(days=30),
        due_date=invoice.due_date + timedelta(days=30),
        amount_due=Decimal("10000"),
    )


def _record(landlord, invoice, amount, method="cash", **extra):
    api = APIClient()
    api.force_authenticate(user=landlord)
    return api.post(
        "/api/v1/payments/record/",
        {"invoice": invoice.id, "method": method, "amount": amount, **extra},
        format="json",
    )


def _mpesa(landlord, invoice, amount, code="SIR4K7X2QP"):
    return _record(landlord, invoice, amount, method="mpesa", mpesa_receipt_number=code)


@pytest.mark.django_db
class TestTheReceipt:
    def test_it_goes_to_the_tenant(self, landlord, invoice, texts):
        _record(landlord, invoice, "5000")
        assert texts[0][0] == invoice.tenancy.tenant_id

    def test_it_sets_each_item_on_its_own_line(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000")
        today = timezone.localdate()
        left = invoice.amount_due - 5000
        assert texts[0][1].split("\n") == [
            f"Hi {invoice.tenancy.tenant.first_name},",
            "Payment received. Thank you.",
            "",
            f"{invoice.tenancy.unit.property.name} {invoice.tenancy.unit.unit_number}",
            "Amount: KES 5,000",
            "M-Pesa code: SIR4K7X2QP",
            f"Confirmed: {today.day} {today:%b %Y}",
            "",
            f"{invoice.period_start:%B} bill: KES {left:,.0f} left",
        ]

    def test_paying_it_all_says_so(self, landlord, invoice, texts):
        _record(landlord, invoice, str(invoice.amount_due))
        assert texts[0][1].endswith(f"{invoice.period_start:%B} bill: fully paid")

    def test_a_cash_payment_is_called_one(self, landlord, invoice, texts):
        _record(landlord, invoice, "5000")
        assert "Paid by: Cash" in texts[0][1]

    def test_a_bank_payment_quotes_its_reference(self, landlord, invoice, texts):
        _record(landlord, invoice, "5000", method="bank", bank_reference="FT123")
        assert "Bank ref: FT123" in texts[0][1]

    def test_it_uses_only_plain_sms_characters(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000")
        assert texts[0][1].isascii()

    def test_a_refused_payment_sends_nothing(self, landlord, invoice, texts):
        _record(landlord, invoice, str(invoice.amount_due + 1))
        assert texts == []


@pytest.mark.django_db
class TestConfirmingAnMpesaPayment:
    def test_it_is_kept_as_mpesa(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000")
        assert Payment.objects.get(invoice=invoice).method == Payment.Method.MPESA

    def test_it_keeps_the_code(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000", code=" sir4k7x2qp ")
        assert Payment.objects.get(invoice=invoice).mpesa_receipt_number == "SIR4K7X2QP"

    def test_it_says_who_confirmed_it(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000")
        assert Payment.objects.get(invoice=invoice).recorded_by == landlord

    def test_it_needs_a_code(self, landlord, invoice, texts):
        assert _record(landlord, invoice, "5000", method="mpesa").status_code == 400

    def test_a_badly_formed_code_is_refused(self, landlord, invoice, texts):
        assert _mpesa(landlord, invoice, "5000", code="12 34").status_code == 400

    def test_the_same_code_twice_is_refused(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000")
        assert _mpesa(landlord, invoice, "5000").status_code == 400

    def test_a_repeated_code_adds_nothing_to_the_bill(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000")
        _mpesa(landlord, invoice, "5000")
        invoice.refresh_from_db()
        assert invoice.amount_paid == Decimal("5000")

    def test_a_repeated_code_sends_no_second_receipt(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, "5000")
        _mpesa(landlord, invoice, "5000")
        assert len(texts) == 1

    def test_a_closed_bill_is_refused(self, landlord, invoice, texts):
        _record(landlord, invoice, str(invoice.amount_due))
        assert _mpesa(landlord, invoice, "1000").status_code == 400

    def test_a_closed_bill_leaves_no_credit(self, landlord, invoice, texts):
        _record(landlord, invoice, str(invoice.amount_due))
        _mpesa(landlord, invoice, "1000")
        assert not TenancyCredit.objects.exists()


@pytest.mark.django_db
class TestOneTransferOverSeveralBills:
    def test_it_clears_the_bill_it_was_entered_on(self, landlord, invoice, next_bill, texts):
        _mpesa(landlord, invoice, str(invoice.amount_due + 4000))
        invoice.refresh_from_db()
        assert invoice.status == Invoice.Status.PAID

    def test_the_rest_goes_to_the_next_bill(self, landlord, invoice, next_bill, texts):
        _mpesa(landlord, invoice, str(invoice.amount_due + 4000))
        next_bill.refresh_from_db()
        assert next_bill.amount_paid == Decimal("4000")

    def test_the_receipt_quotes_the_whole_amount(self, landlord, invoice, next_bill, texts):
        _mpesa(landlord, invoice, str(invoice.amount_due + 4000))
        assert f"Amount: KES {invoice.amount_due + 4000:,.0f}" in texts[0][1]

    def test_the_receipt_gives_both_bills(self, landlord, invoice, next_bill, texts):
        _mpesa(landlord, invoice, str(invoice.amount_due + 4000))
        assert texts[0][1].split("\n")[-2:] == [
            f"{invoice.period_start:%B} bill: fully paid",
            f"{next_bill.period_start:%B} bill: KES 6,000 left",
        ]

    def test_anything_over_is_kept_as_credit(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, str(invoice.amount_due + 700))
        assert TenancyCredit.objects.get().amount == Decimal("700")

    def test_the_receipt_says_what_was_kept(self, landlord, invoice, texts):
        _mpesa(landlord, invoice, str(invoice.amount_due + 700))
        assert texts[0][1].endswith("Kept for next bill: KES 700")

    def test_cash_over_the_balance_is_still_refused(self, landlord, invoice, texts):
        assert _record(landlord, invoice, str(invoice.amount_due + 700)).status_code == 400
