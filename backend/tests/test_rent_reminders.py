"""Automatic rent reminders.

The point of these is that nobody has to press anything. The case worth
guarding is the late one: mark_overdue_invoices moves an unpaid invoice out of
PENDING at 00:05, so a reminder query that only looked at PENDING went quiet
from the morning after the due date — precisely when chasing matters.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.notifications.tasks import (
    CHASE_DAYS_AFTER,
    REMINDER_DAYS_BEFORE,
    send_rent_reminders,
)
from apps.payments.models import Invoice


@pytest.fixture
def sent(monkeypatch):
    """Captures what would have gone out, instead of queueing real SMS."""
    captured = []
    from apps.notifications import tasks

    monkeypatch.setattr(
        tasks.send_sms, "delay", lambda uid, msg: captured.append((uid, msg))
    )
    return captured


def _invoice(tenancy, *, due_in_days, status=Invoice.Status.PENDING, number="INV-R", months_ago=0):
    return Invoice.objects.create(
        tenancy=tenancy,
        invoice_number=number,
        amount_due=Decimal("15000.00"),
        due_date=timezone.localdate() + timedelta(days=due_in_days),
        period_start=timezone.localdate() - timedelta(days=31 * months_ago),
        period_end=timezone.localdate() + timedelta(days=30),
        status=status,
    )


class TestBeforeItIsDue:
    @pytest.mark.parametrize("days", REMINDER_DAYS_BEFORE)
    def test_a_reminder_goes_out_on_each_lead_day(self, tenancy, sent, days):
        _invoice(tenancy, due_in_days=days)
        send_rent_reminders()
        assert len(sent) == 1

    def test_the_eve_reminder_says_tomorrow(self, tenancy, sent):
        _invoice(tenancy, due_in_days=1)
        send_rent_reminders()
        assert "due tomorrow" in sent[0][1]

    def test_the_due_day_reminder_says_today(self, tenancy, sent):
        _invoice(tenancy, due_in_days=0)
        send_rent_reminders()
        assert "due TODAY" in sent[0][1]

    def test_no_reminder_on_a_day_that_is_not_a_lead_day(self, tenancy, sent):
        _invoice(tenancy, due_in_days=5)
        send_rent_reminders()
        assert sent == []


class TestAfterItIsLate:
    @pytest.mark.parametrize("days", CHASE_DAYS_AFTER)
    def test_an_overdue_invoice_is_still_chased(self, tenancy, sent, days):
        # The regression this file exists for.
        _invoice(tenancy, due_in_days=-days, status=Invoice.Status.OVERDUE)
        send_rent_reminders()
        assert len(sent) == 1

    def test_the_chase_says_how_late_it_is(self, tenancy, sent):
        _invoice(tenancy, due_in_days=-7, status=Invoice.Status.OVERDUE)
        send_rent_reminders()
        assert "7 days overdue" in sent[0][1]

    def test_a_partially_paid_late_invoice_is_chased(self, tenancy, sent):
        _invoice(tenancy, due_in_days=-3, status=Invoice.Status.PARTIALLY_PAID)
        send_rent_reminders()
        assert len(sent) == 1

    def test_a_late_invoice_is_not_chased_every_single_day(self, tenancy, sent):
        # Being texted daily is how people learn to ignore the texts.
        _invoice(tenancy, due_in_days=-5, status=Invoice.Status.OVERDUE)
        send_rent_reminders()
        assert sent == []


class TestWhoIsLeftAlone:
    def test_a_paid_invoice_is_not_chased(self, tenancy, sent):
        _invoice(tenancy, due_in_days=-3, status=Invoice.Status.PAID)
        send_rent_reminders()
        assert sent == []

    def test_a_cancelled_invoice_is_not_chased(self, tenancy, sent):
        _invoice(tenancy, due_in_days=-3, status=Invoice.Status.CANCELLED)
        send_rent_reminders()
        assert sent == []


class TestTheMessage:
    def test_it_goes_to_the_tenant(self, tenancy, sent, tenant):
        _invoice(tenancy, due_in_days=0)
        send_rent_reminders()
        assert sent[0][0] == tenant.id

    def test_it_quotes_the_payment_code_not_the_unit_number(self, tenancy, sent, unit):
        # The payment code is what the tenant types into M-Pesa; the unit number
        # is the landlord's own label and need not match.
        _invoice(tenancy, due_in_days=0)
        send_rent_reminders()
        assert f"Acc: {unit.payment_code}" in sent[0][1]


class TestOneMessagePerTenant:
    """A tenant months behind used to get a text per unpaid invoice on the same
    morning, each quoting only that month."""

    def _arrears(self, tenancy):
        _invoice(tenancy, due_in_days=0, number="INV-NOW")
        _invoice(tenancy, due_in_days=-30, status=Invoice.Status.OVERDUE,
                 number="INV-OLD", months_ago=1)

    def test_two_unpaid_bills_send_one_message(self, tenancy, sent):
        self._arrears(tenancy)
        send_rent_reminders()
        assert len(sent) == 1

    def test_the_message_quotes_the_total_owed(self, tenancy, sent):
        self._arrears(tenancy)
        send_rent_reminders()
        assert "KES 30,000" in sent[0][1]

    def test_the_message_says_other_bills_are_included(self, tenancy, sent):
        self._arrears(tenancy)
        send_rent_reminders()
        assert "1 other unpaid bill" in sent[0][1]


class TestWhereToPay:
    def test_a_bank_paybill_account_prefix_is_quoted(self, tenancy, sent, unit, settings):
        # Caritas's shared paybill: the account is the landlord's bank account
        # followed by the unit code.
        settings.RENT_PAYBILL = "899790"
        settings.RENT_ACCOUNT_PREFIX = "623943#"
        _invoice(tenancy, due_in_days=0)
        send_rent_reminders()
        # Behind the bank's paybill the account already names the landlord, so
        # the house number is quoted exactly as the landlord set it.
        assert f"Paybill 899790, Acc: 623943#{unit.unit_number}" in sent[0][1]
