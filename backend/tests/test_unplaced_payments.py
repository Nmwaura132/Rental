"""M-Pesa payments Kasa cannot place against an invoice.

These used to end in a log line: the money was in the landlord's account but
nowhere in Kasa, and the tenant who paid was later chased for it.
"""
from __future__ import annotations

from decimal import Decimal

import pytest
from rest_framework.test import APIClient

from apps.payments.models import BankPaymentNotification, Payment
from apps.payments.tasks import process_mpesa_payment


@pytest.fixture
def sent(monkeypatch):
    captured = []
    from apps.notifications import tasks as ntasks

    monkeypatch.setattr(ntasks.send_sms, "delay", lambda uid, msg: captured.append((uid, msg)))
    return captured


def _pay(ref, *, receipt="RUNPLACED1", amount="15000"):
    process_mpesa_payment(
        receipt_number=receipt,
        amount=amount,
        account_ref=ref,
        phone="+254700111111",
        idempotency_key=f"mpesa:{receipt}",
    )


def _held(receipt="RUNPLACED1"):
    return BankPaymentNotification.objects.get(
        bank=BankPaymentNotification.Bank.MPESA, transaction_ref=receipt
    )


class TestAnUnknownReference:
    def test_the_payment_is_kept(self, tenancy, sent):
        _pay("NO-SUCH-UNIT")
        assert _held().amount == Decimal("15000.00")

    def test_it_is_waiting_to_be_matched(self, tenancy, sent):
        _pay("NO-SUCH-UNIT")
        assert _held().status == BankPaymentNotification.Status.UNMATCHED

    def test_nothing_is_recorded_against_any_invoice(self, tenancy, sent):
        _pay("NO-SUCH-UNIT")
        assert not Payment.objects.exists()

    def test_nobody_is_alerted_when_no_landlord_can_be_identified(self, tenancy, sent):
        _pay("NO-SUCH-UNIT")
        assert sent == []


class TestPaidBeforeTheBillExists:
    """Rent paid on the 30th for next month — the unit is known, the invoice
    is not raised yet."""

    def test_the_payment_is_kept(self, tenancy, sent):
        _pay(tenancy.unit.payment_code)
        assert _held().amount == Decimal("15000.00")

    def test_it_belongs_to_the_landlord(self, tenancy, sent, landlord):
        _pay(tenancy.unit.payment_code)
        assert _held().owner == landlord

    def test_the_landlord_is_told(self, tenancy, sent, landlord):
        _pay(tenancy.unit.payment_code)
        assert sent[0][0] == landlord.id

    def test_a_retry_of_the_same_receipt_is_not_held_twice(self, tenancy, sent):
        _pay(tenancy.unit.payment_code)
        _pay(tenancy.unit.payment_code)
        assert BankPaymentNotification.objects.count() == 1

    def test_a_retry_does_not_alert_twice(self, tenancy, sent):
        _pay(tenancy.unit.payment_code)
        _pay(tenancy.unit.payment_code)
        assert len(sent) == 1


class TestPlacingItByHand:
    @pytest.fixture
    def client(self, landlord):
        api = APIClient()
        api.force_authenticate(user=landlord)
        return api

    def _match(self, client, invoice):
        held = _held()
        return client.post(
            f"/api/v1/payments/bank/notifications/{held.id}/match/",
            {"invoice_id": invoice.id},
            format="json",
        )

    def test_the_landlord_can_see_a_payment_with_a_mistyped_reference(self, tenancy, invoice, client, sent):
        # Owner is set from the unit when the payment is held, so it stays
        # visible even when its reference matches nothing the landlord owns.
        invoice.delete()
        _pay(tenancy.unit.payment_code)
        held = _held()
        held.payment_ref = "TYPO"
        held.save(update_fields=["payment_ref"])
        response = client.get("/api/v1/payments/bank/notifications/")
        ids = [row["id"] for row in (response.data.get("results", response.data))]
        assert held.id in ids

    def test_matching_records_it_as_an_mpesa_payment(self, tenancy, invoice, client, sent):
        invoice.delete()
        _pay(tenancy.unit.payment_code)
        from datetime import date, timedelta
        from apps.payments.models import Invoice
        new_invoice = Invoice.objects.create(
            tenancy=tenancy, invoice_number="INV-LATER", amount_due=Decimal("15000.00"),
            due_date=date.today() + timedelta(days=4),
            period_start=date.today().replace(day=1),
            period_end=date.today().replace(day=1) + timedelta(days=30),
        )
        self._match(client, new_invoice)
        assert Payment.objects.get().method == Payment.Method.MPESA

    def test_matching_keeps_the_mpesa_receipt(self, tenancy, invoice, client, sent):
        invoice.delete()
        _pay(tenancy.unit.payment_code)
        from datetime import date, timedelta
        from apps.payments.models import Invoice
        new_invoice = Invoice.objects.create(
            tenancy=tenancy, invoice_number="INV-LATER", amount_due=Decimal("15000.00"),
            due_date=date.today() + timedelta(days=4),
            period_start=date.today().replace(day=1),
            period_end=date.today().replace(day=1) + timedelta(days=30),
        )
        self._match(client, new_invoice)
        assert Payment.objects.get().mpesa_receipt_number == "RUNPLACED1"
