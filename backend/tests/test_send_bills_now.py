"""A landlord sending the coming month's bills early, after reading meters."""
from __future__ import annotations

from datetime import date

import pytest
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks
from apps.payments.models import Invoice
from apps.payments.tasks import bill_month

URL = "/api/v1/payments/invoices/send-month/"


@pytest.fixture
def on(monkeypatch):
    def set_today(day):
        monkeypatch.setattr("django.utils.timezone.localdate", lambda *a, **k: day)
    return set_today


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(notification_tasks.send_sms, "delay", lambda recipient_id, message, **k: sent.append(message))
    return sent


def _as(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


@pytest.mark.django_db
class TestOnTheLastSaturdayOfOctober:
    def test_it_offers_novembers_bills(self, landlord, tenancy, on):
        on(date(2026, 10, 31))
        assert _as(landlord).get(URL).data["period"] == date(2026, 11, 1)

    def test_it_counts_who_is_to_be_billed(self, landlord, tenancy, on):
        on(date(2026, 10, 31))
        assert _as(landlord).get(URL).data["tenancies"] == 1

    def test_sending_bills_each_tenant(self, landlord, tenancy, on):
        on(date(2026, 10, 31))
        _as(landlord).post(URL)
        assert Invoice.objects.filter(tenancy=tenancy, period_start=date(2026, 11, 1)).exists()

    def test_the_bill_is_due_on_the_fifth(self, landlord, tenancy, on):
        on(date(2026, 10, 31))
        _as(landlord).post(URL)
        assert Invoice.objects.get(period_start=date(2026, 11, 1)).due_date == date(2026, 11, 5)

    def test_each_tenant_is_texted_their_bill(self, landlord, tenancy, on, texts):
        on(date(2026, 10, 31))
        _as(landlord).post(URL)
        assert "November bill" in texts[0]


@pytest.mark.django_db
class TestNothingIsSentTwice:
    def test_sending_again_sends_nothing(self, landlord, tenancy, on, texts):
        on(date(2026, 10, 31))
        _as(landlord).post(URL)
        _as(landlord).post(URL)
        assert len(texts) == 1

    def test_the_run_on_the_first_finds_them_sent(self, landlord, tenancy, on, texts):
        on(date(2026, 10, 31))
        _as(landlord).post(URL)
        bill_month(date(2026, 11, 1))
        assert len(texts) == 1


@pytest.mark.django_db
class TestOnlyTheirOwnTenants:
    def test_another_landlords_tenants_are_not_billed(self, landlord, tenancy, on, django_user_model):
        other = django_user_model.objects.create_user(
            phone_number="+254700999000", password="Other@Test1", first_name="O", last_name="L",
            role=django_user_model.Role.LANDLORD,
        )
        on(date(2026, 10, 31))
        _as(other).post(URL)
        assert not Invoice.objects.filter(period_start=date(2026, 11, 1)).exists()

    def test_a_tenant_cannot_send_bills(self, tenant, tenancy, on):
        on(date(2026, 10, 31))
        assert _as(tenant).post(URL).status_code == 403


@pytest.mark.django_db
def test_early_in_the_month_it_offers_this_months(landlord, tenancy, on):
    on(date(2026, 11, 3))
    assert _as(landlord).get(URL).data["period"] == date(2026, 11, 1)
