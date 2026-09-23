"""Recording the eTIMS receipt issued for rent received.

KRA cross-checks declared rental income against their eTIMS records, so rent
reported in the MRI statement needs the receipt behind it to be visible — and
visible BEFORE filing, while the landlord can still do something about it.
"""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.models import Payment
from apps.payments.mri import mri_summary, rent_roll


PERIOD_START = date.today().replace(day=1)
PERIOD_END = (
    PERIOD_START.replace(year=PERIOD_START.year + 1, month=1)
    if PERIOD_START.month == 12
    else PERIOD_START.replace(month=PERIOD_START.month + 1)
) - timedelta(days=1)


def _confirm(invoice, amount, *, key, receipt=None):
    return Payment.objects.create(
        invoice=invoice,
        method=Payment.Method.MPESA,
        status=Payment.Status.CONFIRMED,
        amount=Decimal(amount),
        idempotency_key=key,
        paid_at=timezone.now(),
        etims_receipt_number=receipt,
    )


@pytest.fixture
def client(landlord):
    api = APIClient()
    api.force_authenticate(user=landlord)
    return api


class TestRecordingTheNumber:
    def test_a_landlord_can_attach_a_receipt_number(self, client, invoice):
        payment = _confirm(invoice, "15000.00", key="etims:set")
        response = client.post(
            f"/api/v1/payments/{payment.id}/etims-receipt/",
            {"etims_receipt_number": "0090001234567890"},
            format="json",
        )
        assert response.status_code == 200

    def test_the_number_is_stored(self, client, invoice):
        payment = _confirm(invoice, "15000.00", key="etims:stored")
        client.post(
            f"/api/v1/payments/{payment.id}/etims-receipt/",
            {"etims_receipt_number": "0090001234567890"},
            format="json",
        )
        payment.refresh_from_db()
        assert payment.etims_receipt_number == "0090001234567890"

    def test_an_empty_number_is_refused(self, client, invoice):
        payment = _confirm(invoice, "15000.00", key="etims:empty")
        response = client.post(
            f"/api/v1/payments/{payment.id}/etims-receipt/",
            {"etims_receipt_number": "   "},
            format="json",
        )
        assert response.status_code == 400

    def test_the_amount_cannot_be_changed_through_it(self, client, invoice):
        # The whole reason this is a narrow action: confirmed money stays put.
        payment = _confirm(invoice, "15000.00", key="etims:amount")
        client.post(
            f"/api/v1/payments/{payment.id}/etims-receipt/",
            {"etims_receipt_number": "009000123", "amount": "1.00"},
            format="json",
        )
        payment.refresh_from_db()
        assert payment.amount == Decimal("15000.00")

    def test_another_landlords_payment_is_not_reachable(self, invoice, django_user_model):
        payment = _confirm(invoice, "15000.00", key="etims:stranger")
        stranger = django_user_model.objects.create_user(
            phone_number="+254700111222",
            password="Other@Test1",
            first_name="Other",
            last_name="Landlord",
            role=django_user_model.Role.LANDLORD,
        )
        api = APIClient()
        api.force_authenticate(user=stranger)
        response = api.post(
            f"/api/v1/payments/{payment.id}/etims-receipt/",
            {"etims_receipt_number": "009000123"},
            format="json",
        )
        assert response.status_code == 404


class TestTheRentRoll:
    def test_the_row_carries_the_receipt(self, invoice, landlord):
        _confirm(invoice, "15000.00", key="roll:etims", receipt="009000111")
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert rows[0]["etims_receipts"] == ["009000111"]

    def test_one_receipt_covering_two_part_payments_is_listed_once(self, invoice, landlord):
        _confirm(invoice, "9000.00", key="roll:part1", receipt="009000222")
        _confirm(invoice, "6000.00", key="roll:part2", receipt="009000222")
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert rows[0]["etims_receipts"] == ["009000222"]

    def test_rent_with_no_receipt_lists_none(self, invoice, landlord):
        _confirm(invoice, "15000.00", key="roll:noetims")
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert rows[0]["etims_receipts"] == []


class TestTheFilingWarning:
    def test_unreceipted_rent_is_counted(self, invoice, landlord):
        _confirm(invoice, "15000.00", key="sum:missing")
        summary = mri_summary(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert summary["payments_missing_etims_receipt"] == 1

    def test_receipted_rent_is_not_counted(self, invoice, landlord):
        _confirm(invoice, "15000.00", key="sum:present", receipt="009000333")
        summary = mri_summary(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert summary["payments_missing_etims_receipt"] == 0

    def test_a_period_with_no_rent_warns_about_nothing(self, invoice, landlord):
        summary = mri_summary(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert summary["payments_missing_etims_receipt"] == 0


class TestTheGuardStillHolds:
    """The receipt is a hole deliberately cut in payment immutability. These
    pin its edges, so a later change cannot quietly widen it into the money."""

    def test_the_amount_cannot_be_saved_directly(self, invoice):
        from django.core.exceptions import ValidationError

        payment = _confirm(invoice, "15000.00", key="guard:amount")
        payment.amount = Decimal("1.00")
        with pytest.raises(ValidationError):
            payment.save(update_fields=["amount"])

    def test_the_amount_cannot_ride_along_with_the_receipt(self, invoice):
        from django.core.exceptions import ValidationError

        payment = _confirm(invoice, "15000.00", key="guard:ride")
        payment.amount = Decimal("1.00")
        payment.etims_receipt_number = "009000444"
        with pytest.raises(ValidationError):
            payment.save(update_fields=["etims_receipt_number", "amount"])

    def test_a_confirmed_payment_still_cannot_be_deleted(self, invoice):
        from django.core.exceptions import ValidationError

        payment = _confirm(invoice, "15000.00", key="guard:delete")
        with pytest.raises(ValidationError):
            payment.delete()
