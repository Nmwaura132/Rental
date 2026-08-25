"""Monthly Rental Income figures for KRA filing.

MRI is charged on gross rent RECEIVED, so these tests exist mainly to pin down
that an unpaid invoice creates no tax liability — the mistake that would have a
landlord paying tax on money they never got.
"""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.payments.mri import mri_summary, rent_roll
from apps.payments.models import Invoice, Payment


PERIOD_START = date.today().replace(day=1)
PERIOD_END = PERIOD_START + timedelta(days=27)


def _confirm(invoice, amount, *, key, when=None):
    return Payment.objects.create(
        invoice=invoice,
        method=Payment.Method.MPESA,
        status=Payment.Status.CONFIRMED,
        amount=Decimal(amount),
        idempotency_key=key,
        paid_at=when or timezone.now(),
    )


@pytest.fixture
def summary(landlord):
    def _run(start=PERIOD_START, end=PERIOD_END):
        return mri_summary(owner=landlord, period_start=start, period_end=end)
    return _run


class TestGrossRentReceived:
    def test_a_confirmed_payment_counts_towards_gross_rent(self, invoice, summary):
        _confirm(invoice, "15000.00", key="mri:one")
        assert summary()["gross_rent_received"] == Decimal("15000.00")

    def test_an_unpaid_invoice_contributes_nothing(self, invoice, summary):
        # The whole point of taxing receipts: billing a tenant who has not paid
        # must not create a liability.
        assert summary()["gross_rent_received"] == Decimal("0")

    def test_a_pending_payment_is_not_counted(self, invoice, summary):
        Payment.objects.create(
            invoice=invoice,
            method=Payment.Method.MPESA,
            status=Payment.Status.PENDING,
            amount=Decimal("15000.00"),
            idempotency_key="mri:pending",
        )
        assert summary()["gross_rent_received"] == Decimal("0")

    def test_two_payments_on_one_invoice_are_summed(self, invoice, summary):
        _confirm(invoice, "9000.00", key="mri:part-1")
        _confirm(invoice, "6000.00", key="mri:part-2")
        assert summary()["gross_rent_received"] == Decimal("15000.00")

    def test_a_payment_before_the_period_is_excluded(self, invoice, summary):
        _confirm(
            invoice, "15000.00", key="mri:early",
            when=timezone.now() - timedelta(days=90),
        )
        assert summary()["gross_rent_received"] == Decimal("0")

    def test_another_landlords_rent_is_excluded(self, invoice, summary, django_user_model):
        from apps.properties.models import Property, Unit
        from apps.tenants.models import Tenancy

        stranger = django_user_model.objects.create_user(
            phone_number="+254700999888",
            password="Other@Test1",
            first_name="Other",
            last_name="Landlord",
            role=django_user_model.Role.LANDLORD,
        )
        other_property = Property.objects.create(owner=stranger, name="Not Ours")
        other_unit = Unit.objects.create(
            property=other_property,
            unit_number="Z9",
            unit_type=Unit.UnitType.ONE_BED,
            rent_amount=Decimal("20000.00"),
            deposit_amount=Decimal("20000.00"),
        )
        other_tenancy = Tenancy.objects.create(
            tenant=invoice.tenancy.tenant,
            unit=other_unit,
            start_date=date.today() - timedelta(days=10),
            rent_amount=Decimal("20000.00"),
            deposit_amount=Decimal("20000.00"),
        )
        other_invoice = Invoice.objects.create(
            tenancy=other_tenancy,
            invoice_number="INV-OTHER-1",
            amount_due=Decimal("20000.00"),
            due_date=date.today(),
            period_start=PERIOD_START,
            period_end=PERIOD_END,
        )
        _confirm(other_invoice, "20000.00", key="mri:stranger")

        assert summary()["gross_rent_received"] == Decimal("0")


class TestTaxDue:
    def test_tax_is_the_configured_rate_of_gross_rent(self, invoice, summary, settings):
        settings.MRI_TAX_RATE = 0.075
        _confirm(invoice, "20000.00", key="mri:rate")
        assert summary()["tax_due"] == Decimal("1500.00")

    def test_a_changed_rate_changes_the_tax(self, invoice, summary, settings):
        # The rate has already moved once and a further change was proposed in
        # the Finance Bill 2026; it must not be baked in.
        settings.MRI_TAX_RATE = 0.10
        _confirm(invoice, "20000.00", key="mri:rate-10")
        assert summary()["tax_due"] == Decimal("2000.00")

    def test_no_rent_means_no_tax(self, invoice, summary):
        assert summary()["tax_due"] == Decimal("0.00")

    def test_the_rate_used_is_reported_back(self, invoice, summary, settings):
        settings.MRI_TAX_RATE = 0.075
        assert summary()["tax_rate"] == Decimal("0.075")


class TestRentRoll:
    def test_a_paying_tenancy_appears_once(self, invoice, landlord):
        _confirm(invoice, "15000.00", key="roll:one")
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert len(rows) == 1

    def test_the_row_reports_rent_actually_received(self, invoice, landlord):
        _confirm(invoice, "9000.00", key="roll:partial")
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert rows[0]["rent_received"] == Decimal("9000.00")

    def test_the_row_carries_the_tenant_kra_pin(self, invoice, landlord):
        tenant = invoice.tenancy.tenant
        tenant.kra_pin = "A012345678Z"
        tenant.save(update_fields=["kra_pin"])
        _confirm(invoice, "15000.00", key="roll:pin")
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert rows[0]["tenant_kra_pin"] == "A012345678Z"

    def test_the_row_carries_the_property_lr_number(self, invoice, landlord):
        prop = invoice.tenancy.unit.property
        prop.lr_number = "LR 209/12345"
        prop.save(update_fields=["lr_number"])
        _confirm(invoice, "15000.00", key="roll:lr")
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert rows[0]["lr_number"] == "LR 209/12345"

    def test_a_tenancy_with_no_payment_is_absent(self, invoice, landlord):
        rows = rent_roll(owner=landlord, period_start=PERIOD_START, period_end=PERIOD_END)
        assert rows == []


class TestMissingPins:
    def test_a_tenant_without_a_pin_is_flagged(self, invoice, summary):
        # eRITS rejects a filing missing tenant PINs, so this has to be visible
        # while there is still time to chase them.
        _confirm(invoice, "15000.00", key="pin:missing")
        assert summary()["tenants_missing_kra_pin"] == ["Test Tenant"]

    def test_a_tenant_with_a_pin_is_not_flagged(self, invoice, summary):
        tenant = invoice.tenancy.tenant
        tenant.kra_pin = "A012345678Z"
        tenant.save(update_fields=["kra_pin"])
        _confirm(invoice, "15000.00", key="pin:present")
        assert summary()["tenants_missing_kra_pin"] == []

    def test_a_non_paying_tenant_is_not_chased_for_a_pin(self, invoice, summary):
        # They contribute nothing to this month's filing, so a missing PIN is
        # not yet a problem for it.
        assert summary()["tenants_missing_kra_pin"] == []
