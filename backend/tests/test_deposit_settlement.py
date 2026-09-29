"""The tenant's deposit when they move out.

The agreement refunds it "less any outstanding arrears, charges on repairs or
bills", and forfeits it if the tenant overstays. This is where landlord and
tenant disputes happen, so every figure is pinned.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

import pytest
from django.core.exceptions import ValidationError
from django.utils import timezone
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks
from apps.payments.models import Invoice, InvoiceLineItem, Payment
from apps.payments.services import apply_confirmed_payment, create_move_in_invoice
from apps.tenants import settlement as deposit
from apps.tenants.models import Tenancy


@pytest.fixture(autouse=True)
def sent(monkeypatch):
    captured = []
    monkeypatch.setattr(
        notification_tasks.send_sms, "delay", lambda uid, msg: captured.append((uid, msg))
    )
    return captured


@pytest.fixture
def leaving(tenancy):
    """A tenancy that has ended, holding a 20,000 deposit."""
    tenancy.deposit_amount = Decimal("20000.00")
    tenancy.deposit_paid = True
    tenancy.status = Tenancy.Status.TERMINATED
    tenancy.save(update_fields=["deposit_amount", "deposit_paid", "status"])
    return tenancy


def _bill(tenancy, amount, months_ago, number):
    start = (timezone.localdate().replace(day=1) - timedelta(days=31 * months_ago)).replace(day=1)
    return Invoice.objects.create(
        tenancy=tenancy, invoice_number=number, amount_due=Decimal(amount),
        due_date=start.replace(day=5), period_start=start,
        period_end=start + timedelta(days=27),
    )


def _settle(tenancy, by, **kw):
    return deposit.settle(tenancy, by=by, **kw)


def _fresh_tenancy(tenant, unit):
    return Tenancy.objects.create(
        tenant=tenant, unit=unit, start_date=timezone.localdate(),
        rent_amount=Decimal("15000.00"), deposit_amount=Decimal("15000.00"),
    )


class TestTheDepositIsKnownToBeHeld:
    def test_paying_the_move_in_bill_marks_the_deposit_held(self, tenant, unit):
        fresh = _fresh_tenancy(tenant, unit)
        invoice, _ = create_move_in_invoice(fresh, notify=False)
        apply_confirmed_payment(
            invoice_id=invoice.pk, method=Payment.Method.MPESA, amount=invoice.amount_due,
            idempotency_key="dep:full", paid_at=timezone.now(),
        )
        fresh.refresh_from_db()
        assert fresh.deposit_paid is True

    def test_paying_only_the_rent_part_does_not(self, tenant, unit):
        fresh = _fresh_tenancy(tenant, unit)
        invoice, _ = create_move_in_invoice(fresh, notify=False)
        apply_confirmed_payment(
            invoice_id=invoice.pk, method=Payment.Method.MPESA, amount=Decimal("15000.00"),
            idempotency_key="dep:part", paid_at=timezone.now(),
        )
        fresh.refresh_from_db()
        assert fresh.deposit_paid is False


class TestAClearMoveOut:
    def test_the_whole_deposit_is_refunded(self, leaving, landlord):
        assert _settle(leaving, landlord).refund_due == Decimal("20000.00")

    def test_the_tenant_owes_nothing(self, leaving, landlord):
        assert _settle(leaving, landlord).tenant_owes == Decimal("0")

    def test_the_tenant_is_sent_an_itemised_statement(
        self, leaving, landlord, tenant, sent, django_capture_on_commit_callbacks
    ):
        with django_capture_on_commit_callbacks(execute=True):
            _settle(leaving, landlord)
        assert (sent[-1][0], "Refund due to you: KES 20,000" in sent[-1][1]) == (tenant.id, True)


class TestUnpaidBillsComeFirst:
    def test_arrears_are_taken_from_the_deposit(self, leaving, landlord):
        _bill(leaving, "8000.00", 1, "INV-ARR-1")
        assert _settle(leaving, landlord).applied_to_arrears == Decimal("8000.00")

    def test_the_bill_is_closed(self, leaving, landlord):
        bill = _bill(leaving, "8000.00", 1, "INV-ARR-2")
        _settle(leaving, landlord)
        bill.refresh_from_db()
        assert bill.status == Invoice.Status.PAID

    def test_it_is_recorded_as_the_deposit_not_new_money(self, leaving, landlord):
        _bill(leaving, "8000.00", 1, "INV-ARR-3")
        _settle(leaving, landlord)
        assert Payment.objects.get().method == Payment.Method.DEPOSIT

    def test_the_rest_is_refunded(self, leaving, landlord):
        _bill(leaving, "8000.00", 1, "INV-ARR-4")
        assert _settle(leaving, landlord).refund_due == Decimal("12000.00")

    def test_the_oldest_bill_is_settled_first(self, leaving, landlord):
        older = _bill(leaving, "15000.00", 2, "INV-OLD")
        newer = _bill(leaving, "15000.00", 1, "INV-NEW")
        _settle(leaving, landlord)
        older.refresh_from_db()
        newer.refresh_from_db()
        assert (older.status, newer.balance) == (Invoice.Status.PAID, Decimal("10000.00"))

    def test_arrears_beyond_the_deposit_are_still_owed(self, leaving, landlord):
        _bill(leaving, "15000.00", 2, "INV-A")
        _bill(leaving, "15000.00", 1, "INV-B")
        assert _settle(leaving, landlord).tenant_owes == Decimal("10000.00")


class TestDeductions:
    def test_a_deduction_comes_off_the_refund(self, leaving, landlord):
        result = _settle(leaving, landlord, deductions=[{"description": "Repainting", "amount": "6000"}])
        assert result.refund_due == Decimal("14000.00")

    def test_each_deduction_is_kept_with_its_reason(self, leaving, landlord):
        result = _settle(leaving, landlord, deductions=[
            {"description": "Repainting", "amount": "6000"},
            {"description": "Water, final reading", "amount": "450"},
        ])
        assert [d.description for d in result.deductions.all()] == ["Repainting", "Water, final reading"]

    def test_deductions_beyond_the_deposit_are_owed(self, leaving, landlord):
        result = _settle(leaving, landlord, deductions=[{"description": "Broken door", "amount": "25000"}])
        assert (result.refund_due, result.tenant_owes) == (Decimal("0"), Decimal("5000.00"))

    def test_a_deduction_without_a_reason_is_refused(self, leaving, landlord):
        with pytest.raises(ValidationError):
            _settle(leaving, landlord, deductions=[{"description": " ", "amount": "100"}])

    def test_a_zero_deduction_is_refused(self, leaving, landlord):
        with pytest.raises(ValidationError):
            _settle(leaving, landlord, deductions=[{"description": "Cleaning", "amount": "0"}])


class TestForfeiture:
    def test_a_forfeited_deposit_refunds_nothing(self, leaving, landlord):
        result = _settle(leaving, landlord, forfeited=True, notes="Stayed into November.")
        assert result.refund_due == Decimal("0")

    def test_it_still_counts_against_deductions(self, leaving, landlord):
        # Forfeiture keeps the leftover; it does not charge the repairs twice.
        result = _settle(
            leaving, landlord, forfeited=True, notes="Stayed into November.",
            deductions=[{"description": "Repainting", "amount": "6000"}],
        )
        assert result.tenant_owes == Decimal("0")

    def test_a_reason_is_required(self, leaving, landlord):
        with pytest.raises(ValidationError):
            _settle(leaving, landlord, forfeited=True)


class TestWhenItCanHappen:
    def test_not_while_the_tenant_is_still_living_there(self, tenancy, landlord):
        with pytest.raises(ValidationError):
            _settle(tenancy, landlord)

    def test_on_the_last_day_of_notice(self, tenancy, landlord):
        tenancy.notice_given_at = timezone.now() - timedelta(days=40)
        tenancy.notice_effective_date = timezone.localdate()
        tenancy.save(update_fields=["notice_given_at", "notice_effective_date"])
        assert _settle(tenancy, landlord) is not None

    def test_only_once(self, leaving, landlord):
        _settle(leaving, landlord)
        with pytest.raises(ValidationError):
            _settle(leaving, landlord)

    def test_a_deposit_never_paid_refunds_nothing(self, leaving, landlord):
        leaving.deposit_paid = False
        leaving.save(update_fields=["deposit_paid"])
        assert _settle(leaving, landlord).refund_due == Decimal("0")


class TestThroughTheApi:
    def _client(self, user):
        api = APIClient()
        api.force_authenticate(user=user)
        return api

    def test_the_landlord_sees_the_figures_before_settling(self, leaving, landlord):
        _bill(leaving, "8000.00", 1, "INV-P")
        data = self._client(landlord).get(f"/api/v1/tenants/tenancies/{leaving.id}/settlement/").data
        assert (data["settled"], Decimal(str(data["available_after_arrears"]))) == (False, Decimal("12000.00"))

    def test_the_landlord_can_settle(self, leaving, landlord):
        response = self._client(landlord).post(
            f"/api/v1/tenants/tenancies/{leaving.id}/settlement/",
            {"deductions": [{"description": "Repainting", "amount": "6000"}]}, format="json",
        )
        assert Decimal(str(response.data["refund_due"])) == Decimal("14000.00")

    def test_the_tenant_can_read_their_settlement(self, leaving, landlord, tenant):
        _settle(leaving, landlord)
        response = self._client(tenant).get(f"/api/v1/tenants/tenancies/{leaving.id}/settlement/")
        assert response.data["settled"] is True

    def test_the_tenant_cannot_settle_it(self, leaving, tenant):
        response = self._client(tenant).post(
            f"/api/v1/tenants/tenancies/{leaving.id}/settlement/", {}, format="json"
        )
        assert response.status_code == 403

    def test_a_caretaker_cannot_settle_it(self, leaving, caretaker):
        prop = leaving.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        response = self._client(caretaker).post(
            f"/api/v1/tenants/tenancies/{leaving.id}/settlement/", {}, format="json"
        )
        assert response.status_code == 403

    def test_the_refund_can_be_recorded(self, leaving, landlord):
        _settle(leaving, landlord)
        response = self._client(landlord).post(
            f"/api/v1/tenants/tenancies/{leaving.id}/settlement/refund/",
            {"method": "mpesa", "reference": "RKT123XYZ"}, format="json",
        )
        assert response.data["refund_reference"] == "RKT123XYZ"

    def test_the_refund_cannot_be_recorded_twice(self, leaving, landlord):
        _settle(leaving, landlord)
        api = self._client(landlord)
        url = f"/api/v1/tenants/tenancies/{leaving.id}/settlement/refund/"
        api.post(url, {"method": "cash"}, format="json")
        assert api.post(url, {"method": "cash"}, format="json").status_code == 400


class TestKraFigures:
    def test_deposit_applied_to_rent_arrears_counts_as_rent_received(self, leaving, landlord):
        from apps.payments.mri import mri_summary

        bill = _bill(leaving, "8000.00", 0, "INV-MRI")
        InvoiceLineItem.objects.create(
            invoice=bill, description="Rent", charge_type="rent", amount=Decimal("8000.00")
        )
        _settle(leaving, landlord)
        today = timezone.localdate()
        summary = mri_summary(owner=landlord, period_start=today.replace(day=1), period_end=today)
        assert summary["gross_rent_received"] == Decimal("8000.00")


class TestTheDashboard:
    def test_a_deposit_applied_at_move_out_is_not_money_collected(self, leaving, landlord):
        # It arrived at move-in and was counted then.
        from django.core.cache import cache

        _bill(leaving, "8000.00", 0, "INV-DASH")
        _settle(leaving, landlord)
        cache.clear()
        api = APIClient()
        api.force_authenticate(user=landlord)
        data = api.get("/api/v1/payments/dashboard/").data
        assert Decimal(str(data["monthly_collected_kes"])) == Decimal("0")
