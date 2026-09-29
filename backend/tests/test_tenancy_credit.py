"""Money paid beyond what was owed at the time.

A payment used to land entirely on the oldest open bill: a tenant clearing two
months at once had the old bill marked overpaid and this month's still chased,
and anyone paying ahead was chased the same way. Now a payment clears open
bills oldest first and anything left is credit, applied to the next bill.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

import pytest
from django.db.models import Sum
from django.utils import timezone

from apps.notifications import tasks as notification_tasks
from apps.payments.models import BankPaymentNotification, Invoice, Payment, TenancyCredit
from apps.payments.services import allocate_payment, apply_credit, credit_remaining
from apps.payments.tasks import generate_monthly_invoices, process_mpesa_payment

THIS_MONTH = timezone.localdate().replace(day=1)


@pytest.fixture(autouse=True)
def sent(monkeypatch):
    captured = []
    monkeypatch.setattr(
        notification_tasks.send_sms, "delay", lambda uid, msg: captured.append((uid, msg))
    )
    return captured


def _bill(tenancy, amount, months_ago, number):
    start = (THIS_MONTH - timedelta(days=31 * months_ago)).replace(day=1)
    return Invoice.objects.create(
        tenancy=tenancy, invoice_number=number, amount_due=Decimal(amount),
        due_date=start.replace(day=5), period_start=start,
        period_end=start + timedelta(days=27),
    )


def _mpesa(tenancy, amount, receipt="RCRED00001"):
    process_mpesa_payment(
        receipt_number=receipt,
        amount=str(amount),
        account_ref=tenancy.unit.payment_code,
        phone="+254700111111",
        idempotency_key=f"mpesa:{receipt}",
    )


def _refresh(*objs):
    for o in objs:
        o.refresh_from_db()


class TestOnePaymentForSeveralBills:
    def test_both_months_are_cleared(self, tenancy, django_capture_on_commit_callbacks):
        older = _bill(tenancy, "15000.00", 1, "INV-OLD")
        newer = _bill(tenancy, "15000.00", 0, "INV-NEW")
        _mpesa(tenancy, "30000")
        _refresh(older, newer)
        assert (older.status, newer.status) == (Invoice.Status.PAID, Invoice.Status.PAID)

    def test_no_bill_is_overpaid(self, tenancy):
        older = _bill(tenancy, "15000.00", 1, "INV-OLD")
        _bill(tenancy, "15000.00", 0, "INV-NEW")
        _mpesa(tenancy, "30000")
        _refresh(older)
        assert older.amount_paid == Decimal("15000.00")

    def test_a_part_payment_clears_the_oldest_first(self, tenancy):
        older = _bill(tenancy, "15000.00", 1, "INV-OLD")
        newer = _bill(tenancy, "15000.00", 0, "INV-NEW")
        _mpesa(tenancy, "20000")
        _refresh(older, newer)
        assert (older.status, newer.balance) == (Invoice.Status.PAID, Decimal("10000.00"))

    def test_only_the_first_part_carries_the_receipt(self, tenancy):
        _bill(tenancy, "15000.00", 1, "INV-OLD")
        _bill(tenancy, "15000.00", 0, "INV-NEW")
        _mpesa(tenancy, "30000")
        assert list(Payment.objects.order_by("id").values_list("mpesa_receipt_number", flat=True)) == [
            "RCRED00001", None,
        ]

    def test_the_second_part_points_back_to_the_first(self, tenancy):
        _bill(tenancy, "15000.00", 1, "INV-OLD")
        _bill(tenancy, "15000.00", 0, "INV-NEW")
        _mpesa(tenancy, "30000")
        first, second = Payment.objects.order_by("id")
        assert second.carried_from == first

    def test_the_parts_add_up_to_the_money_received(self, tenancy):
        _bill(tenancy, "15000.00", 1, "INV-OLD")
        _bill(tenancy, "15000.00", 0, "INV-NEW")
        _mpesa(tenancy, "30000")
        assert Payment.objects.aggregate(s=Sum("amount"))["s"] == Decimal("30000.00")


class TestPayingMoreThanIsOwed:
    def test_the_excess_is_kept_as_credit(self, invoice):
        _mpesa(invoice.tenancy, "20000")
        assert credit_remaining(invoice.tenancy) == Decimal("5000.00")

    def test_the_bill_is_paid_exactly(self, invoice):
        _mpesa(invoice.tenancy, "20000")
        _refresh(invoice)
        assert invoice.amount_paid == invoice.amount_due

    def test_the_tenant_is_told_about_the_credit(self, invoice, tenant, sent, django_capture_on_commit_callbacks):
        with django_capture_on_commit_callbacks(execute=True):
            _mpesa(invoice.tenancy, "20000")
        assert "KES 5,000 is kept as credit" in sent[-1][1]

    def test_a_retried_callback_creates_no_second_credit(self, invoice):
        _mpesa(invoice.tenancy, "20000")
        _mpesa(invoice.tenancy, "20000")
        assert TenancyCredit.objects.count() == 1


class TestPayingBeforeTheBillExists:
    def test_it_becomes_credit(self, tenancy):
        _mpesa(tenancy, "15000")
        assert credit_remaining(tenancy) == Decimal("15000.00")

    def test_it_is_not_left_for_the_landlord_to_assign(self, tenancy):
        _mpesa(tenancy, "15000")
        assert not BankPaymentNotification.objects.exists()

    def test_the_next_bill_is_paid_from_it(self, tenancy):
        _mpesa(tenancy, "15000")
        generate_monthly_invoices()
        bill = Invoice.objects.get(tenancy=tenancy, period_start=THIS_MONTH)
        assert bill.status == Invoice.Status.PAID

    def test_the_receipt_goes_on_the_payment_made_from_it(self, tenancy):
        _mpesa(tenancy, "15000")
        generate_monthly_invoices()
        assert Payment.objects.get().mpesa_receipt_number == "RCRED00001"

    def test_the_payment_is_dated_when_the_money_arrived(self, tenancy):
        # So it counts for KRA in the month it was received, not when applied.
        allocate_payment(
            tenancy=tenancy, amount=Decimal("15000"), method=Payment.Method.MPESA,
            idempotency_key="early", paid_at=timezone.now() - timedelta(days=20),
            payment_fields={"mpesa_receipt_number": "REARLY0001"},
        )
        _bill(tenancy, "15000.00", 0, "INV-LATE")
        apply_credit(tenancy)
        assert Payment.objects.get().paid_at.date() == (timezone.now() - timedelta(days=20)).date()

    def test_the_bill_sms_says_nothing_is_left_to_pay(self, tenancy, sent):
        _mpesa(tenancy, "15000")
        generate_monthly_invoices()
        assert "Nothing to pay" in sent[-1][1]


class TestCreditSpreadOverBills:
    def test_credit_larger_than_a_bill_carries_on(self, tenancy):
        allocate_payment(
            tenancy=tenancy, amount=Decimal("25000"), method=Payment.Method.MPESA,
            idempotency_key="big", paid_at=timezone.now(),
            payment_fields={"mpesa_receipt_number": "RBIG000001"},
        )
        _bill(tenancy, "15000.00", 0, "INV-A")
        apply_credit(tenancy)
        assert credit_remaining(tenancy) == Decimal("10000.00")

    def test_the_second_use_points_back_to_the_first(self, tenancy):
        allocate_payment(
            tenancy=tenancy, amount=Decimal("25000"), method=Payment.Method.MPESA,
            idempotency_key="big", paid_at=timezone.now(),
            payment_fields={"mpesa_receipt_number": "RBIG000001"},
        )
        _bill(tenancy, "15000.00", 1, "INV-A")
        apply_credit(tenancy)
        _bill(tenancy, "15000.00", 0, "INV-B")
        apply_credit(tenancy)
        first, second = Payment.objects.order_by("id")
        assert (second.carried_from, second.mpesa_receipt_number) == (first, None)


class TestAssigningAHeldPayment:
    def test_an_amount_bigger_than_the_chosen_bill_is_not_overpaid(self, invoice, landlord):
        from apps.payments.bank_reconcile import reconcile_bank_notification

        held = BankPaymentNotification.objects.create(
            bank=BankPaymentNotification.Bank.MPESA, transaction_ref="RHELD00001",
            amount=Decimal("20000.00"), payment_ref="TYPO", credited_at=timezone.now(),
            raw_payload={}, owner=landlord,
        )
        reconcile_bank_notification(held, invoice_id=invoice.pk)
        _refresh(invoice)
        assert (invoice.amount_paid, credit_remaining(invoice.tenancy)) == (
            Decimal("15000.00"), Decimal("5000.00"),
        )


class TestMovingOut:
    @pytest.fixture
    def leaving(self, tenancy):
        from apps.tenants.models import Tenancy

        tenancy.deposit_amount = Decimal("20000.00")
        tenancy.deposit_paid = True
        tenancy.status = Tenancy.Status.TERMINATED
        tenancy.save(update_fields=["deposit_amount", "deposit_paid", "status"])
        return tenancy

    def _credit(self, tenancy, amount):
        allocate_payment(
            tenancy=tenancy, amount=Decimal(amount), method=Payment.Method.MPESA,
            idempotency_key=f"credit:{amount}", paid_at=timezone.now(),
            payment_fields={"mpesa_receipt_number": "RMOVE00001"},
        )

    def test_unused_credit_is_refunded(self, leaving, landlord):
        from apps.tenants.settlement import settle

        self._credit(leaving, "5000")
        assert settle(leaving, by=landlord).refund_due == Decimal("25000.00")

    def test_it_is_refunded_even_if_the_deposit_is_forfeited(self, leaving, landlord):
        # Rent paid ahead is the tenant's money, not security.
        from apps.tenants.settlement import settle

        self._credit(leaving, "5000")
        assert settle(leaving, by=landlord, forfeited=True, notes="Overstayed.").refund_due == Decimal("5000.00")

    def test_credit_clears_unpaid_bills_before_the_deposit(self, leaving, landlord):
        from apps.tenants.settlement import settle

        # Credit first, then a bill it has not yet been applied to.
        self._credit(leaving, "8000")
        _bill(leaving, "8000.00", 1, "INV-ARR")
        result = settle(leaving, by=landlord)
        assert (result.applied_to_arrears, result.refund_due) == (Decimal("0"), Decimal("20000.00"))

    def test_credit_is_not_refunded_twice(self, leaving, landlord):
        from apps.tenants.settlement import settle

        self._credit(leaving, "5000")
        settle(leaving, by=landlord)
        assert credit_remaining(leaving) == Decimal("0")
