"""The first bill a tenant ever sees.

A tenant moving in owes the first month's rent and, unless they have already
handed it over, the deposit. Getting this wrong either lets someone move in
owing nothing on the books, or bills them twice for a deposit they have paid.
"""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest

from apps.payments.models import Invoice
from apps.payments.services import create_move_in_invoice
from apps.tenants.models import Tenancy


@pytest.fixture
def fresh_tenancy(db, tenant, unit):
    return Tenancy.objects.create(
        tenant=tenant,
        unit=unit,
        start_date=date.today(),
        rent_amount=Decimal("15000.00"),
        deposit_amount=Decimal("30000.00"),
    )


class TestWhatIsBilled:
    def test_rent_and_deposit_are_billed_together(self, fresh_tenancy):
        invoice, _ = create_move_in_invoice(fresh_tenancy)
        assert invoice.amount_due == Decimal("45000.00")

    def test_a_paid_deposit_is_not_billed_again(self, fresh_tenancy):
        fresh_tenancy.deposit_paid = True
        fresh_tenancy.save(update_fields=["deposit_paid"])
        invoice, _ = create_move_in_invoice(fresh_tenancy)
        assert invoice.amount_due == Decimal("15000.00")

    def test_the_deposit_is_shown_as_its_own_line(self, fresh_tenancy):
        invoice, _ = create_move_in_invoice(fresh_tenancy)
        deposit_lines = invoice.line_items.filter(charge_type="deposit")
        assert deposit_lines.get().amount == Decimal("30000.00")

    def test_rent_is_shown_as_its_own_line(self, fresh_tenancy):
        invoice, _ = create_move_in_invoice(fresh_tenancy)
        assert invoice.line_items.get(charge_type="rent").amount == Decimal("15000.00")

    def test_no_deposit_line_when_already_paid(self, fresh_tenancy):
        fresh_tenancy.deposit_paid = True
        fresh_tenancy.save(update_fields=["deposit_paid"])
        invoice, _ = create_move_in_invoice(fresh_tenancy)
        assert not invoice.line_items.filter(charge_type="deposit").exists()


class TestDueDate:
    def test_a_move_in_today_is_due_today(self, fresh_tenancy):
        invoice, _ = create_move_in_invoice(fresh_tenancy)
        assert invoice.due_date == date.today()

    def test_a_backdated_tenancy_is_not_born_overdue(self, fresh_tenancy):
        # Landlords enter existing tenants whose term began months ago. Dating
        # the invoice to then would have it arrive already in arrears and
        # immediately trigger the overdue chase.
        fresh_tenancy.start_date = date.today() - timedelta(days=90)
        fresh_tenancy.save(update_fields=["start_date"])
        invoice, _ = create_move_in_invoice(fresh_tenancy)
        assert invoice.due_date == date.today()


class TestRaisedOnlyOnce:
    def test_calling_twice_does_not_bill_twice(self, fresh_tenancy):
        create_move_in_invoice(fresh_tenancy)
        create_move_in_invoice(fresh_tenancy)
        assert Invoice.objects.filter(tenancy=fresh_tenancy).count() == 1

    def test_the_second_call_reports_it_did_not_create(self, fresh_tenancy):
        create_move_in_invoice(fresh_tenancy)
        _, created = create_move_in_invoice(fresh_tenancy)
        assert created is False

    def test_the_monthly_run_does_not_duplicate_it(self, fresh_tenancy):
        from apps.payments.tasks import generate_monthly_invoices

        create_move_in_invoice(fresh_tenancy)
        generate_monthly_invoices()
        assert Invoice.objects.filter(tenancy=fresh_tenancy).count() == 1


class TestThroughTheApi:
    def test_creating_a_tenancy_bills_the_tenant(self, landlord, tenant, unit):
        from rest_framework.test import APIClient

        # The landlord registered this tenant moments earlier, which is what
        # earns them the right to place them in a unit.
        tenant.created_by = landlord
        tenant.save(update_fields=["created_by"])

        client = APIClient()
        client.force_authenticate(user=landlord)
        response = client.post(
            "/api/v1/tenants/tenancies/",
            {
                "tenant": tenant.id,
                "unit": unit.id,
                "start_date": str(date.today()),
                "rent_amount": "15000.00",
                "deposit_amount": "30000.00",
            },
            format="json",
        )
        assert response.status_code == 201
        assert Invoice.objects.filter(tenancy_id=response.data["id"]).exists()


class TestEnteringSomeoneAlreadyLivingThere:
    """A landlord putting existing tenants into Kasa is not moving them in."""

    def _enter(self, landlord, tenant, unit, start):
        from rest_framework.test import APIClient

        tenant.created_by = landlord
        tenant.save(update_fields=["created_by"])
        client = APIClient()
        client.force_authenticate(user=landlord)
        return client.post(
            "/api/v1/tenants/tenancies/",
            {
                "tenant": tenant.id, "unit": unit.id, "start_date": str(start),
                "rent_amount": "15000.00", "deposit_amount": "15000.00", "deposit_paid": True,
            },
            format="json",
        )

    def test_they_get_no_move_in_bill(self, landlord, tenant, unit):
        response = self._enter(landlord, tenant, unit, date(2024, 3, 1))
        assert not Invoice.objects.filter(tenancy_id=response.data["id"]).exists()

    def test_they_get_no_welcome_sms(self, landlord, tenant, unit, monkeypatch):
        from apps.notifications import tasks as notification_tasks

        sent = []
        monkeypatch.setattr(notification_tasks.send_sms, "delay", lambda *a, **k: sent.append(a))
        self._enter(landlord, tenant, unit, date(2024, 3, 1))
        assert sent == []

    def test_someone_moving_in_this_month_is_still_billed(self, landlord, tenant, unit):
        response = self._enter(landlord, tenant, unit, date.today().replace(day=1))
        assert Invoice.objects.filter(tenancy_id=response.data["id"]).exists()


class TestRentAlreadyPaidOnMoveIn:
    """The landlord took the first month's rent in hand before adding them."""

    def _move_in(self, landlord, tenant, unit, **extra):
        from rest_framework.test import APIClient

        tenant.created_by = landlord
        tenant.save(update_fields=["created_by"])
        client = APIClient()
        client.force_authenticate(user=landlord)
        response = client.post(
            "/api/v1/tenants/tenancies/",
            {"tenant": tenant.id, "unit": unit.id, "start_date": str(date.today()),
             "rent_amount": "15000.00", "deposit_amount": "15000.00", **extra},
            format="json",
        )
        return Invoice.objects.get(tenancy_id=response.data["id"])

    def test_the_rent_is_recorded_as_received(self, landlord, tenant, unit):
        bill = self._move_in(landlord, tenant, unit, rent_paid=True)
        assert bill.payments.get().amount == Decimal("15000.00")

    def test_as_cash_the_landlord_entered(self, landlord, tenant, unit):
        bill = self._move_in(landlord, tenant, unit, rent_paid=True)
        payment = bill.payments.get()
        assert (payment.method, payment.recorded_by_id) == ("cash", landlord.id)

    def test_only_the_deposit_is_left_to_pay(self, landlord, tenant, unit):
        bill = self._move_in(landlord, tenant, unit, rent_paid=True)
        assert bill.balance == Decimal("15000.00")

    def test_with_the_deposit_paid_too_nothing_is_owed(self, landlord, tenant, unit):
        bill = self._move_in(landlord, tenant, unit, rent_paid=True, deposit_paid=True)
        assert bill.balance == Decimal("0")

    def test_no_sms_is_sent(self, landlord, tenant, unit, monkeypatch):
        from apps.notifications import tasks as notification_tasks

        sent = []
        monkeypatch.setattr(notification_tasks.send_sms, "delay", lambda *a, **k: sent.append(a))
        self._move_in(landlord, tenant, unit, rent_paid=True)
        assert sent == []

    def test_without_it_the_rent_is_owed(self, landlord, tenant, unit):
        bill = self._move_in(landlord, tenant, unit)
        assert not bill.payments.exists()


class TestExtrasOnMoveIn:
    """Fixed charges like a service charge, billed and paid like the rent."""

    @pytest.fixture
    def service(self, unit):
        from apps.properties.models import PropertyCharge

        return PropertyCharge.objects.create(
            property=unit.property, charge_type="service", name="Service Charge",
            billing_method=PropertyCharge.BillingMethod.FLAT, unit_price=Decimal("500.00"),
        )

    @pytest.fixture
    def water(self, unit):
        from apps.properties.models import PropertyCharge

        return PropertyCharge.objects.create(
            property=unit.property, charge_type="water", name="Water",
            billing_method=PropertyCharge.BillingMethod.METERED, unit_price=Decimal("200.00"),
        )

    def _move_in(self, landlord, tenant, unit, **extra):
        from rest_framework.test import APIClient

        tenant.created_by = landlord
        tenant.save(update_fields=["created_by"])
        client = APIClient()
        client.force_authenticate(user=landlord)
        response = client.post(
            "/api/v1/tenants/tenancies/",
            {"tenant": tenant.id, "unit": unit.id, "start_date": str(date.today()),
             "rent_amount": "15000.00", "deposit_amount": "15000.00", "deposit_paid": True, **extra},
            format="json",
        )
        return Invoice.objects.get(tenancy_id=response.data["id"])

    def test_the_bill_includes_them(self, landlord, tenant, unit, service):
        assert self._move_in(landlord, tenant, unit).amount_due == Decimal("15500.00")

    def test_they_have_their_own_line(self, landlord, tenant, unit, service):
        bill = self._move_in(landlord, tenant, unit)
        assert bill.line_items.get(charge_type="service").amount == Decimal("500.00")

    def test_metered_water_is_left_for_a_later_bill(self, landlord, tenant, unit, service, water):
        bill = self._move_in(landlord, tenant, unit)
        assert not bill.line_items.filter(charge_type="water").exists()

    def test_marked_paid_they_are_recorded_as_received(self, landlord, tenant, unit, service):
        bill = self._move_in(landlord, tenant, unit, extras_paid=True)
        assert bill.payments.get().amount == Decimal("500.00")

    def test_only_the_rent_is_then_left(self, landlord, tenant, unit, service):
        bill = self._move_in(landlord, tenant, unit, extras_paid=True)
        assert bill.balance == Decimal("15000.00")

    def test_rent_and_extras_both_paid_leaves_nothing(self, landlord, tenant, unit, service):
        bill = self._move_in(landlord, tenant, unit, rent_paid=True, extras_paid=True)
        assert bill.balance == Decimal("0")

    def test_extras_paid_with_no_extras_does_nothing(self, landlord, tenant, unit):
        bill = self._move_in(landlord, tenant, unit, extras_paid=True)
        assert not bill.payments.exists()
