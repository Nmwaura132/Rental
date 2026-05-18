"""Money-path regression tests covering the bugs /autoplan and /cso found:
idempotency on M-Pesa receipts, Decimal precision, invoice status transitions."""
from __future__ import annotations

from decimal import Decimal

import pytest

from apps.payments.models import Invoice, Payment
from apps.payments.mpesa import make_idempotency_key
from apps.payments.tasks import process_mpesa_payment


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
