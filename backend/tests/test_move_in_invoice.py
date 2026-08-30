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
        invoice, _ = create_move_in_invoice(fresh_tenancy, notify=False)
        assert invoice.amount_due == Decimal("45000.00")

    def test_a_paid_deposit_is_not_billed_again(self, fresh_tenancy):
        fresh_tenancy.deposit_paid = True
        fresh_tenancy.save(update_fields=["deposit_paid"])
        invoice, _ = create_move_in_invoice(fresh_tenancy, notify=False)
        assert invoice.amount_due == Decimal("15000.00")

    def test_the_deposit_is_shown_as_its_own_line(self, fresh_tenancy):
        invoice, _ = create_move_in_invoice(fresh_tenancy, notify=False)
        deposit_lines = invoice.line_items.filter(charge_type="deposit")
        assert deposit_lines.get().amount == Decimal("30000.00")

    def test_rent_is_shown_as_its_own_line(self, fresh_tenancy):
        invoice, _ = create_move_in_invoice(fresh_tenancy, notify=False)
        assert invoice.line_items.get(charge_type="rent").amount == Decimal("15000.00")

    def test_no_deposit_line_when_already_paid(self, fresh_tenancy):
        fresh_tenancy.deposit_paid = True
        fresh_tenancy.save(update_fields=["deposit_paid"])
        invoice, _ = create_move_in_invoice(fresh_tenancy, notify=False)
        assert not invoice.line_items.filter(charge_type="deposit").exists()


class TestDueDate:
    def test_a_move_in_today_is_due_today(self, fresh_tenancy):
        invoice, _ = create_move_in_invoice(fresh_tenancy, notify=False)
        assert invoice.due_date == date.today()

    def test_a_backdated_tenancy_is_not_born_overdue(self, fresh_tenancy):
        # Landlords enter existing tenants whose term began months ago. Dating
        # the invoice to then would have it arrive already in arrears and
        # immediately trigger the overdue chase.
        fresh_tenancy.start_date = date.today() - timedelta(days=90)
        fresh_tenancy.save(update_fields=["start_date"])
        invoice, _ = create_move_in_invoice(fresh_tenancy, notify=False)
        assert invoice.due_date == date.today()


class TestRaisedOnlyOnce:
    def test_calling_twice_does_not_bill_twice(self, fresh_tenancy):
        create_move_in_invoice(fresh_tenancy, notify=False)
        create_move_in_invoice(fresh_tenancy, notify=False)
        assert Invoice.objects.filter(tenancy=fresh_tenancy).count() == 1

    def test_the_second_call_reports_it_did_not_create(self, fresh_tenancy):
        create_move_in_invoice(fresh_tenancy, notify=False)
        _, created = create_move_in_invoice(fresh_tenancy, notify=False)
        assert created is False

    def test_the_monthly_run_does_not_duplicate_it(self, fresh_tenancy):
        from apps.payments.tasks import generate_monthly_invoices

        create_move_in_invoice(fresh_tenancy, notify=False)
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
