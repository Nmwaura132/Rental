"""A landlord texting their own tenants a message of their own."""
from __future__ import annotations

from decimal import Decimal

import pytest
from rest_framework.test import APIClient

from apps.notifications import tasks as notification_tasks

URL = "/api/v1/notifications/message-tenants/"


@pytest.fixture
def texts(monkeypatch):
    sent = []
    monkeypatch.setattr(
        notification_tasks.send_sms, "delay", lambda recipient_id, message, **k: sent.append((recipient_id, message))
    )
    return sent


def _as(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


def _send(user, **body):
    return _as(user).post(URL, {"message": "Water off Saturday 9am to 1pm.", **body}, format="json")


@pytest.mark.django_db
class TestSending:
    def test_the_tenant_gets_it(self, landlord, tenancy, texts):
        _send(landlord)
        assert texts[0][0] == tenancy.tenant_id

    def test_it_starts_with_the_building(self, landlord, tenancy, texts):
        _send(landlord)
        assert texts[0][1] == f"{tenancy.unit.property.name}: Water off Saturday 9am to 1pm."

    def test_the_landlord_is_told_how_many(self, landlord, tenancy, texts):
        assert _send(landlord).data == {"sent": 1}

    def test_one_building_only(self, landlord, tenancy, texts):
        from apps.properties.models import Property

        other = Property.objects.create(owner=landlord, name="Other Court")
        _send(landlord, property=other.id)
        assert texts == []

    def test_one_tenant_only(self, landlord, tenancy, texts):
        _send(landlord, tenancy=tenancy.id)
        assert len(texts) == 1

    def test_the_count_before_sending(self, landlord, tenancy):
        assert _as(landlord).get(URL).data == {"recipients": 1}


@pytest.mark.django_db
class TestWhatIsRefused:
    def test_an_empty_message(self, landlord, tenancy, texts):
        assert _send(landlord, message="   ").status_code == 400

    def test_a_message_too_long_for_a_text(self, landlord, tenancy, texts):
        assert _send(landlord, message="x" * 301).status_code == 400

    def test_another_landlords_tenants(self, landlord, tenancy, texts, django_user_model):
        other = django_user_model.objects.create_user(
            phone_number="+254700999001", password="Other@Test1", first_name="O", last_name="L",
            role=django_user_model.Role.LANDLORD,
        )
        _send(other, tenancy=tenancy.id)
        assert texts == []

    def test_a_tenant_cannot_send(self, tenant, tenancy, texts):
        assert _send(tenant).status_code == 403

    def test_more_than_ten_a_day(self, landlord, tenancy, texts):
        for _ in range(10):
            _send(landlord)
        assert _send(landlord).status_code == 429

    def test_a_tenant_who_has_left_is_not_texted(self, landlord, tenancy, texts):
        tenancy.status = tenancy.Status.TERMINATED
        tenancy.save(update_fields=["status"])
        assert _send(landlord).status_code == 400
