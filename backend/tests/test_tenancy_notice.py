"""Written notice to end a tenancy, and what happens when it runs out.

Under the landlord's agreement either party may end the tenancy with one
month's notice, and the tenant must vacate before the next payment month
begins. An open-ended tenancy ends this way rather than by reaching a date, so
it is how most Kenyan tenancies actually terminate.
"""
from __future__ import annotations

from datetime import date, timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks
from apps.payments.models import Invoice
from apps.payments.tasks import generate_monthly_invoices
from apps.properties.models import Unit
from apps.tenants.models import Tenancy
from apps.tenants.notice import vacate_by
from apps.tenants.tasks import end_expired_tenancies


@pytest.fixture
def sent(monkeypatch):
    captured = []
    monkeypatch.setattr(
        notification_tasks.send_sms, "delay", lambda uid, msg: captured.append((uid, msg))
    )
    return captured


def _give_notice(user, tenancy, reason=None):
    client = APIClient()
    client.force_authenticate(user=user)
    body = {} if reason is None else {"reason": reason}
    return client.post(
        f"/api/v1/tenants/tenancies/{tenancy.id}/give-notice/", body, format="json"
    )


class TestWhenTheTenantMustBeOut:
    @pytest.mark.parametrize(
        "given, out_by",
        [
            (date(2026, 9, 1), date(2026, 10, 31)),
            (date(2026, 9, 10), date(2026, 10, 31)),
            (date(2026, 9, 30), date(2026, 10, 31)),
            (date(2026, 12, 15), date(2027, 1, 31)),
            (date(2027, 1, 31), date(2027, 2, 28)),
        ],
    )
    def test_the_last_day_of_the_month_after_notice(self, given, out_by):
        # Rent is paid in advance, so they leave at the end of a month they
        # have already paid for — however early or late in a month they said so.
        assert vacate_by(given) == out_by

    def test_the_tenancy_records_that_date(self, tenant, tenancy):
        _give_notice(tenant, tenancy)
        tenancy.refresh_from_db()
        assert tenancy.notice_effective_date == vacate_by(timezone.localdate())

    def test_a_client_cannot_choose_its_own_vacate_date(self, tenant, tenancy):
        client = APIClient()
        client.force_authenticate(user=tenant)
        client.post(
            f"/api/v1/tenants/tenancies/{tenancy.id}/give-notice/",
            {"notice_effective_date": "2020-01-01"},
            format="json",
        )
        tenancy.refresh_from_db()
        assert tenancy.notice_effective_date == vacate_by(timezone.localdate())


class TestATenantGivingNotice:
    def test_a_tenant_can_give_notice_on_their_own_tenancy(self, tenant, tenancy):
        assert _give_notice(tenant, tenancy).status_code == 200

    def test_the_tenants_own_words_are_kept_verbatim(self, tenant, tenancy):
        _give_notice(tenant, tenancy, reason="Relocating to Nakuru for work.")
        tenancy.refresh_from_db()
        assert tenancy.notice_reason == "Relocating to Nakuru for work."

    def test_notice_without_a_reason_is_still_accepted(self, tenant, tenancy):
        # A tenant is not obliged to explain themselves.
        assert _give_notice(tenant, tenancy).status_code == 200

    def test_the_record_says_the_tenant_gave_it(self, tenant, tenancy):
        _give_notice(tenant, tenancy)
        tenancy.refresh_from_db()
        assert tenancy.notice_given_by == tenant

    def test_the_landlord_is_sent_a_message(self, tenant, tenancy, landlord, sent):
        _give_notice(tenant, tenancy)
        assert sent[0][0] == landlord.id

    def test_the_message_names_the_vacate_date(self, tenant, tenancy, sent):
        _give_notice(tenant, tenancy)
        assert vacate_by(timezone.localdate()).strftime("%d %b %Y") in sent[0][1]


class TestALandlordGivingNotice:
    def test_the_landlord_can_end_the_tenancy(self, landlord, tenancy):
        assert _give_notice(landlord, tenancy, reason="Selling the building.").status_code == 200

    def test_a_reason_is_required(self, landlord, tenancy):
        assert _give_notice(landlord, tenancy).status_code == 400

    def test_a_blank_reason_is_not_a_reason(self, landlord, tenancy):
        assert _give_notice(landlord, tenancy, reason="   ").status_code == 400

    def test_the_record_says_the_landlord_gave_it(self, landlord, tenancy):
        _give_notice(landlord, tenancy, reason="Selling the building.")
        tenancy.refresh_from_db()
        assert tenancy.notice_given_by == landlord

    def test_the_tenant_is_told_and_given_the_reason(self, landlord, tenancy, tenant, sent):
        _give_notice(landlord, tenancy, reason="Selling the building.")
        assert (sent[0][0], "Selling the building." in sent[0][1]) == (tenant.id, True)

    def test_the_tenant_is_told_when_they_must_leave(self, landlord, tenancy, sent):
        _give_notice(landlord, tenancy, reason="Selling the building.")
        assert vacate_by(timezone.localdate()).strftime("%d %b %Y") in sent[0][1]

    def test_another_landlord_cannot(self, tenancy, django_user_model):
        stranger = django_user_model.objects.create_user(
            phone_number="+254700555000",
            password="Stranger@Test1",
            first_name="Other",
            last_name="Landlord",
            role=django_user_model.Role.LANDLORD,
        )
        assert _give_notice(stranger, tenancy, reason="x").status_code in (403, 404)


class TestWhoElseCannot:
    def test_a_caretaker_cannot_give_notice(self, caretaker, tenancy):
        # Assigned to the property, so the tenancy IS visible to them — this
        # exercises the guard rather than a 404 from queryset scoping. They
        # manage the building but are not a party to the tenancy.
        prop = tenancy.unit.property
        prop.caretaker = caretaker
        prop.save(update_fields=["caretaker"])
        assert _give_notice(caretaker, tenancy, reason="x").status_code == 403

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

    def test_the_landlord_cannot_replace_the_tenants_notice(self, tenant, landlord, tenancy):
        _give_notice(tenant, tenancy)
        assert _give_notice(landlord, tenancy, reason="x").status_code == 409

    def test_a_second_notice_does_not_move_the_vacate_date(self, tenant, tenancy):
        # Otherwise a party could roll the date forward indefinitely.
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


class TestWhenTheNoticeRunsOut:
    def _notice_ended(self, tenancy, days_ago):
        tenancy.notice_given_at = timezone.now() - timedelta(days=40)
        tenancy.notice_effective_date = timezone.localdate() - timedelta(days=days_ago)
        tenancy.save(update_fields=["notice_given_at", "notice_effective_date"])

    def test_the_tenancy_ends_the_day_after_the_last_day(self, tenancy, sent):
        self._notice_ended(tenancy, days_ago=1)
        end_expired_tenancies()
        tenancy.refresh_from_db()
        assert tenancy.status == Tenancy.Status.TERMINATED

    def test_it_does_not_end_on_the_last_day_itself(self, tenancy, sent):
        # They may occupy the unit right through the effective date.
        self._notice_ended(tenancy, days_ago=0)
        end_expired_tenancies()
        tenancy.refresh_from_db()
        assert tenancy.status == Tenancy.Status.ACTIVE

    def test_the_end_date_is_the_last_day_they_had(self, tenancy, sent):
        self._notice_ended(tenancy, days_ago=1)
        end_expired_tenancies()
        tenancy.refresh_from_db()
        assert tenancy.end_date == tenancy.notice_effective_date

    def test_the_unit_becomes_vacant(self, tenancy, sent):
        self._notice_ended(tenancy, days_ago=1)
        end_expired_tenancies()
        tenancy.unit.refresh_from_db()
        assert tenancy.unit.status == Unit.Status.VACANT

    def test_the_landlord_is_told(self, tenancy, landlord, sent):
        self._notice_ended(tenancy, days_ago=1)
        end_expired_tenancies()
        assert sent[0][0] == landlord.id

    def test_a_tenancy_with_no_notice_is_left_alone(self, tenancy, sent):
        end_expired_tenancies()
        tenancy.refresh_from_db()
        assert tenancy.status == Tenancy.Status.ACTIVE

    def test_running_it_twice_ends_it_once(self, tenancy, sent):
        self._notice_ended(tenancy, days_ago=1)
        end_expired_tenancies()
        end_expired_tenancies()
        assert len(sent) == 1


class TestSomeoneWhoHasLeftIsNotBilled:
    THIS_MONTH = timezone.localdate().replace(day=1)

    def test_a_tenancy_whose_notice_ended_last_month_is_not_billed(self, tenancy, sent):
        # Even if end_expired_tenancies has not run yet.
        tenancy.notice_effective_date = self.THIS_MONTH - timedelta(days=1)
        tenancy.save(update_fields=["notice_effective_date"])
        generate_monthly_invoices()
        assert not Invoice.objects.filter(tenancy=tenancy, period_start=self.THIS_MONTH).exists()

    def test_a_tenancy_leaving_at_the_end_of_this_month_is_billed(self, tenancy, sent):
        # They are staying through the month, and have paid it in advance.
        tenancy.notice_effective_date = vacate_by(self.THIS_MONTH - timedelta(days=1))
        tenancy.save(update_fields=["notice_effective_date"])
        generate_monthly_invoices()
        assert Invoice.objects.filter(tenancy=tenancy, period_start=self.THIS_MONTH).exists()
