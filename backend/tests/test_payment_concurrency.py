from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from threading import Barrier

import pytest
from django.db import close_old_connections, connection
from django.utils import timezone

from apps.payments.models import Payment
from apps.payments.services import apply_confirmed_payment


def _apply_after_barrier(barrier, invoice_id, amount, key):
    close_old_connections()
    try:
        barrier.wait()
        return apply_confirmed_payment(
            invoice_id=invoice_id,
            method=Payment.Method.CASH,
            amount=amount,
            idempotency_key=key,
            paid_at=timezone.now(),
        )
    finally:
        close_old_connections()


@pytest.mark.django_db(transaction=True)
def test_concurrent_payments_do_not_lose_invoice_totals(invoice):
    if connection.vendor != "mysql":
        pytest.skip("Row-lock concurrency is validated against MySQL in CI.")
    barrier = Barrier(2)
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(
                _apply_after_barrier,
                barrier,
                invoice.pk,
                Decimal("1000.00"),
                "concurrent:first",
            ),
            executor.submit(
                _apply_after_barrier,
                barrier,
                invoice.pk,
                Decimal("2000.00"),
                "concurrent:second",
            ),
        ]
        for future in futures:
            future.result()

    invoice.refresh_from_db()
    assert invoice.amount_paid == Decimal("3000.00")
    assert Payment.objects.filter(invoice=invoice).count() == 2


@pytest.mark.django_db(transaction=True)
def test_concurrent_duplicate_payment_is_applied_once(invoice):
    if connection.vendor != "mysql":
        pytest.skip("Row-lock concurrency is validated against MySQL in CI.")
    barrier = Barrier(2)
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(
                _apply_after_barrier,
                barrier,
                invoice.pk,
                Decimal("1000.00"),
                "concurrent:duplicate",
            )
            for _ in range(2)
        ]
        results = [future.result() for future in futures]

    invoice.refresh_from_db()
    assert invoice.amount_paid == Decimal("1000.00")
    assert sorted(created for _, created in results) == [False, True]
    assert Payment.objects.filter(idempotency_key="concurrent:duplicate").count() == 1
