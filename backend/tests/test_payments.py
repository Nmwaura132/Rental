"""Money-path regression tests covering the bugs /autoplan and /cso found:
idempotency on M-Pesa receipts, Decimal precision, invoice status transitions."""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from django.core.exceptions import ValidationError
from django.utils import timezone

from apps.payments.models import Invoice, MpesaSTKRequest, Payment
from apps.payments.mpesa import make_idempotency_key
from apps.payments.services import apply_confirmed_payment
from apps.payments.tasks import (
    mark_overdue_invoices,
    process_mpesa_payment,
    reconcile_pending_stk_transactions,
)


@pytest.mark.django_db
def test_overdue_processing_marks_open_past_due_invoices(invoice):
    invoice.due_date = date.today() - timedelta(days=1)
    invoice.status = Invoice.Status.PARTIALLY_PAID
    invoice.amount_paid = Decimal("1000.00")
    invoice.save()

    assert mark_overdue_invoices() == 1

    invoice.refresh_from_db()
    assert invoice.status == Invoice.Status.OVERDUE


@pytest.mark.django_db
def test_stk_query_success_without_receipt_requires_manual_review(invoice, monkeypatch):
    request = MpesaSTKRequest.objects.create(
        checkout_request_id="ws_CO_TEST_RECONCILE",
        merchant_request_id="merchant-test",
        phone="+254700111111",
        amount=Decimal("15000.00"),
        account_ref=invoice.lease.unit.unit_number,
        invoice=invoice,
    )
    MpesaSTKRequest.objects.filter(pk=request.pk).update(
        created_at=timezone.now() - timedelta(minutes=10)
    )
    monkeypatch.setattr(
        "apps.payments.mpesa.stk_query",
        lambda checkout_id: {"ResultCode": "0", "ResultDesc": "Processed"},
    )

    reconcile_pending_stk_transactions()

    request.refresh_from_db()
    assert request.status == MpesaSTKRequest.Status.REQUIRES_REVIEW
    assert not Payment.objects.filter(invoice=invoice).exists()


@pytest.mark.django_db
def test_make_idempotency_key_stable():
    # Same receipt -> same key, every time, no nondeterminism.
    assert make_idempotency_key("RLJ3KLJ4KL") == make_idempotency_key("RLJ3KLJ4KL")
    assert make_idempotency_key("AAA") != make_idempotency_key("BBB")
    assert len(make_idempotency_key("AAA")) == 60


@pytest.mark.django_db
def test_duplicate_mpesa_callback_does_not_double_pay(invoice, lease):
    """Safaricom retries confirmation up to 3x. The idempotency_key + skip
    inside the locked block must prevent a second Payment row."""
    receipt = "RTESTREC1"
    key = make_idempotency_key(receipt)

    process_mpesa_payment(
        receipt_number=receipt,
        amount="15000",
        account_ref=lease.unit.unit_number,
        phone="+254700111111",
        idempotency_key=key,
    )
    process_mpesa_payment(  # duplicate
        receipt_number=receipt,
        amount="15000",
        account_ref=lease.unit.unit_number,
        phone="+254700111111",
        idempotency_key=key,
    )

    payments = Payment.objects.filter(mpesa_receipt_number=receipt)
    assert payments.count() == 1, "duplicate callback created a second payment"

    invoice.refresh_from_db()
    assert invoice.amount_paid == Decimal("15000.00")
    assert invoice.status == Invoice.Status.PAID


@pytest.mark.django_db
def test_amount_is_parsed_as_decimal_not_float(invoice, lease):
    """C2B amounts arrive as strings/numbers. The task must coerce via
    Decimal(str(...)) so cents don't drift across additions."""
    # 100.50 chosen because float() would store 100.49999... and break ledgers.
    process_mpesa_payment(
        receipt_number="RTESTFLOAT",
        amount="100.50",
        account_ref=lease.unit.unit_number,
        phone="+254700111111",
        idempotency_key=make_idempotency_key("RTESTFLOAT"),
    )
    payment = Payment.objects.get(mpesa_receipt_number="RTESTFLOAT")
    assert payment.amount == Decimal("100.50")


@pytest.mark.django_db
def test_partial_payment_marks_invoice_partially_paid(invoice, lease):
    process_mpesa_payment(
        receipt_number="RPARTIAL",
        amount="5000",
        account_ref=lease.unit.unit_number,
        phone="+254700111111",
        idempotency_key=make_idempotency_key("RPARTIAL"),
    )
    invoice.refresh_from_db()
    assert invoice.amount_paid == Decimal("5000.00")
    assert invoice.status == Invoice.Status.PARTIALLY_PAID


@pytest.mark.django_db
def test_partial_payment_keeps_past_due_invoice_overdue(invoice, lease):
    invoice.due_date = date.today() - timedelta(days=1)
    invoice.status = Invoice.Status.OVERDUE
    invoice.save()

    process_mpesa_payment(
        receipt_number="ROVERDUE",
        amount="5000",
        account_ref=lease.unit.unit_number,
        phone="+254700111111",
        idempotency_key=make_idempotency_key("ROVERDUE"),
    )

    invoice.refresh_from_db()
    assert invoice.status == Invoice.Status.OVERDUE


@pytest.mark.django_db
def test_invalid_account_ref_does_not_create_payment(lease):
    """A wrong BillRefNumber means no matching lease — skip silently."""
    process_mpesa_payment(
        receipt_number="RUNKNOWN",
        amount="5000",
        account_ref="DOES-NOT-EXIST",
        phone="+254700111111",
        idempotency_key=make_idempotency_key("RUNKNOWN"),
    )
    assert not Payment.objects.filter(mpesa_receipt_number="RUNKNOWN").exists()


@pytest.mark.django_db
def test_confirmed_payment_is_immutable(invoice):
    payment = Payment.objects.create(
        invoice=invoice,
        method=Payment.Method.CASH,
        status=Payment.Status.CONFIRMED,
        amount=Decimal("1000.00"),
        idempotency_key="manual:immutable-test",
        paid_at=timezone.now(),
    )

    payment.amount = Decimal("1.00")
    with pytest.raises(ValidationError):
        payment.save()

    with pytest.raises(ValidationError):
        payment.delete()


@pytest.mark.django_db
def test_apply_confirmed_payment_updates_invoice_once(invoice):
    payment, created = apply_confirmed_payment(
        invoice_id=invoice.pk,
        method=Payment.Method.CASH,
        amount=Decimal("1000.00"),
        idempotency_key="manual:service-test",
        paid_at=timezone.now(),
    )
    duplicate, duplicate_created = apply_confirmed_payment(
        invoice_id=invoice.pk,
        method=Payment.Method.CASH,
        amount=Decimal("1000.00"),
        idempotency_key="manual:service-test",
        paid_at=timezone.now(),
    )

    invoice.refresh_from_db()
    assert created is True
    assert duplicate_created is False
    assert duplicate.pk == payment.pk
    assert invoice.amount_paid == Decimal("1000.00")
