"""Read tracking for notifications.

The app has always filtered and styled on "is_read", but nothing recorded it,
so every notification read as unread forever and the bell badge could never
clear. These cover the field that makes those checks mean something.
"""
from __future__ import annotations

import pytest
from rest_framework.test import APIClient

from apps.notifications.models import Notification


def _notify(user, message="Rent received."):
    return Notification.objects.create(
        recipient=user, channel=Notification.Channel.SMS, message=message
    )


def _client(user):
    client = APIClient()
    client.force_authenticate(user=user)
    return client


class TestUnreadCount:
    def test_a_new_notification_counts_as_unread(self, tenant):
        _notify(tenant)
        resp = _client(tenant).get("/api/v1/notifications/unread-count/")
        assert resp.data["unread"] == 1

    def test_an_empty_inbox_counts_zero(self, tenant):
        # The badge must be able to reach zero — it never could before.
        resp = _client(tenant).get("/api/v1/notifications/unread-count/")
        assert resp.data["unread"] == 0

    def test_reading_clears_the_count(self, tenant):
        _notify(tenant)
        client = _client(tenant)
        client.post("/api/v1/notifications/mark-read/")
        assert client.get("/api/v1/notifications/unread-count/").data["unread"] == 0

    def test_another_users_notifications_are_not_counted(self, tenant, landlord):
        _notify(landlord)
        resp = _client(tenant).get("/api/v1/notifications/unread-count/")
        assert resp.data["unread"] == 0


class TestMarkingRead:
    def test_marking_read_reports_how_many_changed(self, tenant):
        _notify(tenant)
        _notify(tenant, "Second one.")
        resp = _client(tenant).post("/api/v1/notifications/mark-read/")
        assert resp.data["marked_read"] == 2

    def test_marking_twice_changes_nothing_the_second_time(self, tenant):
        _notify(tenant)
        client = _client(tenant)
        client.post("/api/v1/notifications/mark-read/")
        assert client.post("/api/v1/notifications/mark-read/").data["marked_read"] == 0

    def test_a_specific_notification_can_be_marked(self, tenant):
        first = _notify(tenant)
        _notify(tenant, "Still unread.")
        _client(tenant).post(
            "/api/v1/notifications/mark-read/", {"ids": [first.id]}, format="json"
        )
        first.refresh_from_db()
        assert first.read_at is not None

    def test_marking_one_leaves_the_others_unread(self, tenant):
        first = _notify(tenant)
        other = _notify(tenant, "Still unread.")
        _client(tenant).post(
            "/api/v1/notifications/mark-read/", {"ids": [first.id]}, format="json"
        )
        other.refresh_from_db()
        assert other.read_at is None

    def test_a_user_cannot_mark_someone_elses_notification(self, tenant, landlord):
        theirs = _notify(landlord)
        _client(tenant).post(
            "/api/v1/notifications/mark-read/", {"ids": [theirs.id]}, format="json"
        )
        theirs.refresh_from_db()
        assert theirs.read_at is None

    def test_a_malformed_ids_value_is_rejected(self, tenant):
        resp = _client(tenant).post(
            "/api/v1/notifications/mark-read/", {"ids": "not-a-list"}, format="json"
        )
        assert resp.status_code == 400

    def test_marking_read_requires_signing_in(self):
        assert APIClient().post("/api/v1/notifications/mark-read/").status_code == 401


class TestListingExposesReadState:
    def test_an_unread_notification_reports_is_read_false(self, tenant):
        _notify(tenant)
        resp = _client(tenant).get("/api/v1/notifications/")
        assert resp.data["results"][0]["is_read"] is False

    def test_a_read_notification_reports_is_read_true(self, tenant):
        _notify(tenant)
        client = _client(tenant)
        client.post("/api/v1/notifications/mark-read/")
        resp = client.get("/api/v1/notifications/")
        assert resp.data["results"][0]["is_read"] is True
