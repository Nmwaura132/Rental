"""The building statement: one row per house per month, with what each bill
charged and what was paid towards rent, water and service charge."""
from __future__ import annotations

from decimal import Decimal
from io import BytesIO

import pytest
from django.utils import timezone
from openpyxl import load_workbook
from rest_framework.test import APIClient

from apps.payments import report_views
from apps.payments.models import Invoice, InvoiceLineItem, Payment
from apps.payments.services import apply_confirmed_payment


@pytest.fixture
def bill(invoice):
    """Rent 15,000 (the fixture's), service 500, and 11 units of water at 200."""
    InvoiceLineItem.objects.create(invoice=invoice, charge_type="rent", description="Rent", amount=invoice.amount_due)
    InvoiceLineItem.objects.create(invoice=invoice, charge_type="service", description="Service Charge", amount=Decimal("500"))
    InvoiceLineItem.objects.create(
        invoice=invoice, charge_type="water", description="Water", amount=Decimal("2200"),
        previous_reading=Decimal("0"), current_reading=Decimal("11"), units_consumed=Decimal("11"),
        unit_price=Decimal("200"), current_read_on=timezone.localdate(),
    )
    invoice.amount_due += Decimal("2700")
    invoice.save(update_fields=["amount_due"])
    return invoice


def _pay(bill, amount, code="UK4S88RZHZ"):
    apply_confirmed_payment(
        invoice_id=bill.pk, method=Payment.Method.MPESA, amount=Decimal(amount),
        idempotency_key=f"mpesa:{code}", paid_at=timezone.now(),
        payment_fields={"mpesa_receipt_number": code},
    )


def _get(user, prop, **params):
    api = APIClient()
    api.force_authenticate(user=user)
    return api.get("/api/v1/payments/reports/", {"type": "statement", "property": prop.id, **params})


def _row(landlord, prop):
    return _get(landlord, prop).data["months"][0]["rows"][0]


@pytest.mark.django_db
class TestTheStatement:
    def test_it_has_a_month_per_billed_month(self, landlord, property_, bill):
        assert [m["month"] for m in _get(landlord, property_).data["months"]] == [f"{bill.period_start:%Y-%m}"]

    def test_a_row_names_the_house_and_tenant(self, landlord, property_, bill):
        row = _row(landlord, property_)
        assert (row["unit"], row["tenant"]) == (bill.tenancy.unit.unit_number, bill.tenancy.tenant.get_full_name())

    def test_a_row_gives_the_water_working(self, landlord, property_, bill):
        row = _row(landlord, property_)
        assert (row["water_previous"], row["water_current"], row["water_units"], row["water_price"], row["water_billed"]) == (
            "0.00", "11.00", "11.00", "200.00", "2200.00")

    def test_a_paid_bill_shows_every_charge_paid(self, landlord, property_, bill):
        _pay(bill, bill.amount_due)
        row = _row(landlord, property_)
        assert (row["rent_paid"], row["water_paid"], row["service_paid"], row["balance"]) == (
            str(bill.tenancy.rent_amount), "2200.00", "500.00", "0.00")

    def test_a_part_payment_goes_to_rent_first(self, landlord, property_, bill):
        _pay(bill, bill.tenancy.rent_amount + 100)
        row = _row(landlord, property_)
        assert (row["rent_paid"], row["service_paid"], row["water_paid"]) == (
            str(bill.tenancy.rent_amount), "100.00", "0.00")

    def test_it_says_how_it_was_paid(self, landlord, property_, bill):
        _pay(bill, bill.amount_due)
        assert _row(landlord, property_)["paid_via"] == "M-Pesa UK4S88RZHZ"

    def test_the_month_is_totalled(self, landlord, property_, bill):
        _pay(bill, "5000")
        totals = _get(landlord, property_).data["months"][0]["totals"]
        assert (totals["billed"], totals["paid"], totals["balance"]) == (
            str(bill.amount_due), "5000.00", str(bill.amount_due - 5000))

    def test_a_deposit_paid_on_entry_shows_on_the_first_bill(self, landlord, property_, bill):
        bill.tenancy.__class__.objects.filter(pk=bill.tenancy_id).update(deposit_paid=True)
        assert _row(landlord, property_)["deposit_paid"] == str(bill.tenancy.deposit_amount)

    def test_a_deposit_paid_on_entry_is_counted_as_received(self, landlord, property_, bill):
        bill.tenancy.__class__.objects.filter(pk=bill.tenancy_id).update(deposit_paid=True)
        _pay(bill, bill.amount_due)
        assert _row(landlord, property_)["received"] == str(bill.amount_due + bill.tenancy.deposit_amount)

    def test_a_deposit_on_entry_stays_out_of_the_bill_total(self, landlord, property_, bill):
        bill.tenancy.__class__.objects.filter(pk=bill.tenancy_id).update(deposit_paid=True)
        assert _row(landlord, property_)["billed"] == str(bill.amount_due)

    def test_an_unpaid_deposit_is_not_shown_as_paid(self, landlord, property_, bill):
        assert _row(landlord, property_)["deposit_paid"] == "0"

    def test_a_held_deposit_is_listed(self, landlord, property_, bill):
        bill.tenancy.__class__.objects.filter(pk=bill.tenancy_id).update(deposit_paid=True)
        deposit = _get(landlord, property_).data["deposits"][0]
        assert (deposit["status"], deposit["held"]) == ("Held", str(bill.tenancy.deposit_amount))

    def test_a_billed_deposit_is_counted_once(self, landlord, property_, bill):
        InvoiceLineItem.objects.create(invoice=bill, charge_type="deposit", description="Security deposit", amount=Decimal("1000"))
        Invoice.objects.filter(pk=bill.pk).update(amount_due=bill.amount_due + 1000)
        bill.refresh_from_db()
        _pay(bill, bill.amount_due)
        assert _row(landlord, property_)["deposit_paid"] == "1000.00"

    def test_a_cancelled_bill_is_left_out(self, landlord, property_, bill):
        Invoice.objects.filter(pk=bill.pk).update(status=Invoice.Status.CANCELLED)
        assert _get(landlord, property_).data["months"] == []

    def test_one_month_can_be_picked(self, landlord, property_, bill):
        assert _get(landlord, property_, month="1999-01").data["months"] == []

    def test_a_caretaker_cannot_see_it(self, caretaker, property_, bill):
        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        assert _get(caretaker, property_).status_code == 403

    def test_another_landlord_cannot_see_it(self, tenant, property_, bill):
        assert _get(tenant, property_).status_code == 403


@pytest.mark.django_db
class TestTheSpreadsheet:
    @pytest.fixture
    def uploaded(self, monkeypatch):
        files = {}
        monkeypatch.setattr(report_views, "upload_private_file",
                            lambda key, content, content_type, content_disposition=None: files.setdefault(key, content) and key)
        monkeypatch.setattr(report_views, "private_file_url", lambda key: f"https://files.test/{key}")
        return files

    def _sheet(self, landlord, property_, uploaded):
        _get(landlord, property_, download="xlsx")
        return load_workbook(BytesIO(next(iter(uploaded.values())))).active

    def test_it_gives_a_link(self, landlord, property_, bill, uploaded):
        assert _get(landlord, property_, download="xlsx").data["file_url"].endswith(".xlsx")

    def test_it_has_the_headings(self, landlord, property_, bill, uploaded):
        sheet = self._sheet(landlord, property_, uploaded)
        assert [c.value for c in sheet[3]][:4] == ["Month", "House", "Tenant", "Rent paid"]

    def test_a_row_carries_the_figures(self, landlord, property_, bill, uploaded):
        _pay(bill, bill.amount_due)
        sheet = self._sheet(landlord, property_, uploaded)
        assert [c.value for c in sheet[4]][6:10] == [11, 200, 2200, 2200]

    def test_it_ends_with_a_grand_total(self, landlord, property_, bill, uploaded):
        _pay(bill, bill.amount_due)
        sheet = self._sheet(landlord, property_, uploaded)
        totals = next(r for r in sheet.iter_rows(values_only=True) if r[0] == "All months")
        assert totals[14] == bill.amount_due

    def test_it_has_a_deposits_sheet(self, landlord, property_, bill, uploaded):
        bill.tenancy.__class__.objects.filter(pk=bill.tenancy_id).update(deposit_paid=True)
        _get(landlord, property_, download="xlsx")
        book = load_workbook(BytesIO(next(iter(uploaded.values()))))
        assert [c.value for c in book["Deposits"][4]][4:] == ["Held", bill.tenancy.deposit_amount]
