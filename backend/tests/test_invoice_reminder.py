"""A landlord's manual reminder about one bill.

Reminders already go out on their own around the due date, so this is a nudge
for a single bill and is limited to once a day.
"""
from __future__ import annotations

import pytest
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks
from apps.payments.models import Invoice


@pytest.fixture(autouse=True)
def sent(monkeypatch):
    captured = []
    monkeypatch.setattr(
        notification_tasks.send_sms, "delay", lambda uid, msg: captured.append((uid, msg))
    )
    return captured


def _remind(user, invoice):
    api = APIClient()
    api.force_authenticate(user=user)
    return api.post(f"/api/v1/payments/invoices/{invoice.id}/remind/")


class TestSendingAReminder:
    def test_the_landlord_can_remind_the_tenant(self, landlord, invoice):
        assert _remind(landlord, invoice).status_code == 200

    def test_it_goes_to_the_tenant(self, landlord, invoice, tenant, sent):
        _remind(landlord, invoice)
        assert sent[0][0] == tenant.id

    def test_it_says_how_much_is_owed(self, landlord, invoice, sent):
        _remind(landlord, invoice)
        assert f"KES {invoice.balance:,.0f}" in sent[0][1]

    def test_it_says_how_to_pay(self, landlord, invoice, sent):
        _remind(landlord, invoice)
        assert "Paybill" in sent[0][1]


class TestNotTwiceInADay:
    def test_a_second_reminder_is_refused(self, landlord, invoice):
        _remind(landlord, invoice)
        assert _remind(landlord, invoice).status_code == 429

    def test_the_second_sends_nothing(self, landlord, invoice, sent):
        _remind(landlord, invoice)
        _remind(landlord, invoice)
        assert len(sent) == 1


class TestWhoAndWhen:
    def test_a_paid_bill_needs_no_reminder(self, landlord, invoice):
        invoice.status = Invoice.Status.PAID
        invoice.save(update_fields=["status"])
        assert _remind(landlord, invoice).status_code == 400

    def test_a_tenant_cannot_send_one(self, tenant, invoice):
        assert _remind(tenant, invoice).status_code == 403

    def test_a_caretaker_cannot_send_one(self, caretaker, invoice):
        prop = invoice.tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        assert _remind(caretaker, invoice).status_code == 403

    def test_another_landlord_cannot_reach_it(self, invoice, django_user_model):
        stranger = django_user_model.objects.create_user(
            phone_number="+254700888999", password="Other@Test1",
            first_name="O", last_name="L", role=django_user_model.Role.LANDLORD,
        )
        assert _remind(stranger, invoice).status_code == 404
