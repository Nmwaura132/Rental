"""A tenant's written 30-day notice to vacate.

An open-ended tenancy ends by notice rather than by reaching a date, so this is
how most Kenyan tenancies actually terminate.
"""
from __future__ import annotations

from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.tenants.models import Tenancy
from apps.tenants.views import NOTICE_PERIOD_DAYS


def _give_notice(user, tenancy, reason=None):
    client = APIClient()
    client.force_authenticate(user=user)
    body = {} if reason is None else {"reason": reason}
    return client.post(
        f"/api/v1/tenants/tenancies/{tenancy.id}/give-notice/", body, format="json"
    )


class TestGivingNotice:
    def test_a_tenant_can_give_notice_on_their_own_tenancy(self, tenant, tenancy):
        assert _give_notice(tenant, tenancy).status_code == 200

    def test_the_vacate_date_is_a_full_notice_period_away(self, tenant, tenancy):
        _give_notice(tenant, tenancy)
        tenancy.refresh_from_db()
        expected = timezone.localdate() + timedelta(days=NOTICE_PERIOD_DAYS)
        assert tenancy.notice_effective_date == expected

    def test_the_notice_period_is_thirty_days(self):
        assert NOTICE_PERIOD_DAYS == 30

    def test_the_tenants_own_words_are_kept_verbatim(self, tenant, tenancy):
        _give_notice(tenant, tenancy, reason="Relocating to Nakuru for work.")
        tenancy.refresh_from_db()
        assert tenancy.notice_reason == "Relocating to Nakuru for work."

    def test_notice_without_a_reason_is_still_accepted(self, tenant, tenancy):
        # A tenant is not obliged to explain themselves.
        assert _give_notice(tenant, tenancy).status_code == 200

    def test_the_tenancy_records_when_notice_was_given(self, tenant, tenancy):
        _give_notice(tenant, tenancy)
        tenancy.refresh_from_db()
        assert tenancy.notice_given_at is not None

    def test_a_client_cannot_choose_its_own_vacate_date(self, tenant, tenancy):
        # Sent as a field the API does not read; the server still fixes the date.
        client = APIClient()
        client.force_authenticate(user=tenant)
        client.post(
            f"/api/v1/tenants/tenancies/{tenancy.id}/give-notice/",
            {"notice_effective_date": "2020-01-01"},
            format="json",
        )
        tenancy.refresh_from_db()
        assert tenancy.notice_effective_date == timezone.localdate() + timedelta(
            days=NOTICE_PERIOD_DAYS
        )


class TestWhoMayGiveNotice:
    def test_a_landlord_cannot_give_notice_for_their_tenant(self, landlord, tenancy):
        # A landlord ending a tenancy is an eviction — a different process with
        # different protections, not something to smuggle through this endpoint.
        assert _give_notice(landlord, tenancy).status_code == 403

    def test_a_caretaker_cannot_give_notice(self, caretaker, tenancy):
        # Assigned to the property, so the tenancy IS visible to them — this
        # exercises the guard rather than a 404 from queryset scoping.
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        assert _give_notice(caretaker, tenancy).status_code == 403

    def test_another_tenant_cannot_give_notice_on_someone_elses_home(
        self, tenancy, django_user_model
    ):
        stranger = django_user_model.objects.create_user(
            phone_number="+254700444000",
            password="Stranger@Test1",
            first_name="Not",
            last_name="Yours",
            role=django_user_model.Role.TENANT,
        )
        assert _give_notice(stranger, tenancy).status_code in (403, 404)


class TestNoticeIsGivenOnce:
    def test_a_second_notice_is_refused(self, tenant, tenancy):
        _give_notice(tenant, tenancy)
        assert _give_notice(tenant, tenancy).status_code == 409

    def test_a_second_notice_does_not_move_the_vacate_date(self, tenant, tenancy):
        # Otherwise a tenant could roll the date forward indefinitely.
        _give_notice(tenant, tenancy)
        tenancy.refresh_from_db()
        first = tenancy.notice_effective_date

        _give_notice(tenant, tenancy, reason="changed my mind")
        tenancy.refresh_from_db()
        assert tenancy.notice_effective_date == first

    def test_notice_cannot_be_given_on_a_terminated_tenancy(self, tenant, tenancy):
        tenancy.status = Tenancy.Status.TERMINATED
        tenancy.save(update_fields=["status"])
        assert _give_notice(tenant, tenancy).status_code == 400


class TestLandlordIsTold:
    def test_the_landlord_is_sent_a_message(self, tenant, tenancy, landlord, monkeypatch):
        sent = []
        from apps.tenants import views as tenancy_views

        monkeypatch.setattr(
            tenancy_views.send_sms, "delay", lambda uid, msg: sent.append((uid, msg))
        )
        _give_notice(tenant, tenancy)
        assert sent[0][0] == landlord.id

    def test_the_message_names_the_vacate_date(
        self, tenant, tenancy, landlord, monkeypatch
    ):
        sent = []
        from apps.tenants import views as tenancy_views

        monkeypatch.setattr(
            tenancy_views.send_sms, "delay", lambda uid, msg: sent.append((uid, msg))
        )
        _give_notice(tenant, tenancy)
        expected = (timezone.localdate() + timedelta(days=NOTICE_PERIOD_DAYS)).strftime("%d %b %Y")
        assert expected in sent[0][1]
