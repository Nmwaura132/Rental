"""What a tenant sees on opening the app: the bill to pay, what to pay it to,
and what the landlord holds for them.
"""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.payments.models import Invoice, InvoiceLineItem, MpesaSTKRequest, Payment, TenancyCredit
from apps.payments.services import apply_confirmed_payment


def _client(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


def _home(user):
    return _client(user).get("/api/v1/payments/dashboard/").data


def _last_months_bill(tenancy):
    last_month = (date.today().replace(day=1) - timedelta(days=1)).replace(day=1)
    return Invoice.objects.create(
        tenancy=tenancy,
        invoice_number="INV-TEST-000000",
        amount_due=Decimal("15000.00"),
        amount_paid=Decimal("0"),
        due_date=last_month + timedelta(days=4),
        period_start=last_month,
        period_end=last_month + timedelta(days=29),
        status=Invoice.Status.OVERDUE,
    )


def _pay_in_full(invoice, key="manual:home-1"):
    apply_confirmed_payment(
        invoice_id=invoice.pk,
        method=Payment.Method.CASH,
        amount=invoice.amount_due,
        idempotency_key=key,
        paid_at=timezone.now(),
    )


class TestTheBillToPay:
    def test_it_is_the_open_bill(self, tenant, invoice):
        assert _home(tenant)["current_bill"]["id"] == invoice.id

    def test_a_part_paid_bill_is_still_the_one_to_pay(self, tenant, invoice):
        invoice.amount_paid = Decimal("5000.00")
        invoice.status = Invoice.Status.PARTIALLY_PAID
        invoice.save(update_fields=["amount_paid", "status"])
        assert _home(tenant)["current_bill"]["id"] == invoice.id

    def test_a_part_paid_bill_shows_only_what_is_left(self, tenant, invoice):
        invoice.amount_paid = Decimal("5000.00")
        invoice.status = Invoice.Status.PARTIALLY_PAID
        invoice.save(update_fields=["amount_paid", "status"])
        assert _home(tenant)["current_bill"]["balance"] == Decimal("10000.00")

    def test_the_oldest_open_bill_comes_first(self, tenant, tenancy, invoice):
        older = _last_months_bill(tenancy)
        assert _home(tenant)["current_bill"]["id"] == older.id

    def test_it_counts_the_bills_still_open(self, tenant, tenancy, invoice):
        _last_months_bill(tenancy)
        assert _home(tenant)["open_bills"] == 2

    def test_a_paid_bill_is_not_offered(self, tenant, invoice):
        _pay_in_full(invoice)
        assert _home(tenant)["current_bill"] is None

    def test_it_carries_the_breakdown(self, tenant, invoice):
        InvoiceLineItem.objects.create(
            invoice=invoice, description="Rent", charge_type="rent", amount=Decimal("15000.00")
        )
        InvoiceLineItem.objects.create(
            invoice=invoice, description="Water", charge_type="water", amount=Decimal("450.00")
        )
        lines = _home(tenant)["current_bill"]["lines"]
        assert [line["description"] for line in lines] == ["Rent", "Water"]

    def test_the_total_owed_covers_every_open_bill(self, tenant, tenancy, invoice):
        _last_months_bill(tenancy)
        assert _home(tenant)["outstanding_balance"] == Decimal("30000.00")


class TestWhereToPay:
    def test_the_account_is_the_landlords_account_and_the_house(self, tenant, tenancy, settings):
        settings.RENT_PAYBILL = "899790"
        settings.RENT_ACCOUNT_PREFIX = "623943#"
        assert _home(tenant)["pay_account"] == "623943#A1"

    def test_the_paybill_is_the_one_to_pay_to(self, tenant, tenancy, settings):
        settings.RENT_PAYBILL = "899790"
        assert _home(tenant)["mpesa_paybill"] == "899790"

    def test_a_prompt_is_offered_when_the_paybill_can_send_one(self, tenant, tenancy, settings):
        settings.STK_PUSH_ENABLED = True
        assert _home(tenant)["stk_enabled"] is True

    def test_no_prompt_is_offered_on_a_shared_paybill(self, tenant, tenancy, settings):
        settings.STK_PUSH_ENABLED = False
        assert _home(tenant)["stk_enabled"] is False


class TestWhatTheLandlordHolds:
    def test_credit_from_paying_ahead_is_shown(self, tenant, tenancy):
        TenancyCredit.objects.create(
            tenancy=tenancy,
            idempotency_key="credit-1",
            amount=Decimal("3000.00"),
            remaining=Decimal("3000.00"),
            method=Payment.Method.MPESA,
            paid_at=timezone.now(),
        )
        assert _home(tenant)["credit"] == Decimal("3000.00")

    def test_credit_already_used_is_not_shown(self, tenant, tenancy):
        TenancyCredit.objects.create(
            tenancy=tenancy,
            idempotency_key="credit-1",
            amount=Decimal("3000.00"),
            remaining=Decimal("0.00"),
            method=Payment.Method.MPESA,
            paid_at=timezone.now(),
        )
        assert _home(tenant)["credit"] == Decimal("0")

    def test_a_paid_deposit_is_shown_as_held(self, tenant, tenancy):
        tenancy.deposit_paid = True
        tenancy.save(update_fields=["deposit_paid"])
        assert _home(tenant)["deposit_held"] == Decimal("30000.00")

    def test_a_deposit_not_yet_paid_is_not_held(self, tenant, tenancy):
        assert _home(tenant)["deposit_held"] == 0


class TestTheLastPayment:
    def test_it_names_the_month_paid_for(self, tenant, invoice):
        _pay_in_full(invoice)
        assert _home(tenant)["last_paid"]["period_start"] == invoice.period_start

    def test_it_says_how_much_was_paid(self, tenant, invoice):
        _pay_in_full(invoice)
        assert _home(tenant)["last_paid"]["amount"] == invoice.amount_due

    def test_there_is_none_before_anything_is_paid(self, tenant, invoice):
        assert _home(tenant)["last_paid"] is None


class TestReachingTheLandlord:
    def test_the_landlords_number_is_there_to_call(self, tenant, tenancy, landlord):
        assert _home(tenant)["landlord_phone"] == landlord.phone_number

    def test_the_landlord_is_named(self, tenant, tenancy, landlord):
        assert _home(tenant)["landlord_name"] == landlord.get_full_name()


class TestNoticeToVacate:
    def _give(self, tenancy, by, reason=""):
        tenancy.notice_given_at = timezone.now()
        tenancy.notice_effective_date = date.today() + timedelta(days=30)
        tenancy.notice_given_by = by
        tenancy.notice_reason = reason
        tenancy.save()

    def test_there_is_no_notice_by_default(self, tenant, tenancy):
        assert _home(tenant)["notice_by"] is None

    def test_notice_the_tenant_gave_is_theirs(self, tenant, tenancy):
        self._give(tenancy, tenant)
        assert _home(tenant)["notice_by"] == "tenant"

    def test_notice_the_landlord_gave_says_so(self, tenant, tenancy, landlord):
        self._give(tenancy, landlord, "Selling the building")
        assert _home(tenant)["notice_by"] == "landlord"

    def test_the_landlords_reason_is_shown_to_the_tenant(self, tenant, tenancy, landlord):
        self._give(tenancy, landlord, "Selling the building")
        assert _home(tenant)["notice_reason"] == "Selling the building"

    def test_the_tenants_own_reason_is_not_played_back(self, tenant, tenancy):
        self._give(tenancy, tenant, "Moving for work")
        assert _home(tenant)["notice_reason"] == ""

    def test_notice_with_no_giver_on_record_is_the_tenants(self, tenant, tenancy):
        self._give(tenancy, None)
        assert _home(tenant)["notice_by"] == "tenant"


class TestTheirOwnPhone:
    def test_it_is_hinted_not_spelled_out(self, tenant, tenancy):
        assert _home(tenant)["phone_hint"] == "0700 ••• 111"


class TestPromptsSwitchedOff:
    def test_a_prompt_is_refused(self, tenant, invoice, settings):
        settings.STK_PUSH_ENABLED = False
        response = _client(tenant).post("/api/v1/payments/stk/push/", {"invoice_id": invoice.id})
        assert response.status_code == 400

    def test_the_refusal_points_to_the_paybill(self, tenant, invoice, settings):
        settings.STK_PUSH_ENABLED = False
        response = _client(tenant).post("/api/v1/payments/stk/push/", {"invoice_id": invoice.id})
        assert "paybill" in response.data["error"].lower()


class TestPaymentsNameTheirMonth:
    def test_a_payment_carries_the_month_of_its_bill(self, tenant, invoice):
        _pay_in_full(invoice)
        rows = _client(tenant).get("/api/v1/payments/").data["results"]
        assert rows[0]["period_start"] == invoice.period_start.isoformat()


class TestWatchingAPrompt:
    def _prompt(self, invoice, tenant):
        return MpesaSTKRequest.objects.create(
            checkout_request_id="ws_CO_TEST_1",
            merchant_request_id="merchant-1",
            phone=tenant.phone_number,
            amount=invoice.balance,
            account_ref="A1",
            invoice=invoice,
        )

    def _status(self, tenant):
        return _client(tenant).get(
            "/api/v1/payments/stk/status/", {"checkout_request_id": "ws_CO_TEST_1"}
        ).data

    def test_it_says_when_the_prompt_was_sent(self, tenant, invoice):
        request = self._prompt(invoice, tenant)
        assert self._status(tenant)["created_at"] == request.created_at

    def test_it_says_when_the_outcome_last_changed(self, tenant, invoice):
        request = self._prompt(invoice, tenant)
        assert self._status(tenant)["updated_at"] == request.updated_at
