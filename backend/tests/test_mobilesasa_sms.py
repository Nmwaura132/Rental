"""SMS goes out through MobileSasa. The network is the boundary that is faked."""
from __future__ import annotations

import pytest
import requests

from apps.notifications import tasks
from apps.notifications.models import Notification


class _Reply:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self.ok = 200 <= status_code < 300
        self._body = body
        self.text = str(body)

    def json(self):
        return self._body


@pytest.fixture
def mobilesasa(monkeypatch, settings):
    settings.MOBILESASA_API_KEY = "key-123"
    settings.MOBILESASA_SENDER_ID = "KASA"
    sent = {}

    def reply_with(status_code=200, body=None):
        def post(url, json, headers, timeout):
            sent.update(url=url, json=json, headers=headers)
            return _Reply(status_code, body if body is not None else
                          {"status": True, "responseCode": "0200", "messageId": "msg-1"})
        monkeypatch.setattr(tasks._requests, "post", post)
        return sent

    return reply_with


def _send(user, message="Rent is due"):
    # .apply runs the task in-process; conftest only stubs .delay.
    return tasks.send_sms.apply(args=[user.id, message])


class TestWhatIsSent:
    def test_it_goes_to_mobilesasa(self, tenant, mobilesasa):
        sent = mobilesasa()
        _send(tenant)
        assert sent["url"] == "https://api.mobilesasa.com/v1/send/message"

    def test_it_carries_the_api_key(self, tenant, mobilesasa):
        sent = mobilesasa()
        _send(tenant)
        assert sent["headers"]["Authorization"] == "Bearer key-123"

    def test_the_number_is_sent_as_stored(self, tenant, mobilesasa):
        sent = mobilesasa()
        _send(tenant)
        assert sent["json"]["phone"] == "+254700111111"

    def test_it_uses_the_registered_sender_id(self, tenant, mobilesasa):
        sent = mobilesasa()
        _send(tenant)
        assert sent["json"]["senderID"] == "KASA"

    def test_the_message_is_sent_as_written(self, tenant, mobilesasa):
        sent = mobilesasa()
        _send(tenant, "Your bill is ready")
        assert sent["json"]["message"] == "Your bill is ready"


class TestWhatIsRecorded:
    def test_a_delivered_message_is_recorded_as_sent(self, tenant, mobilesasa):
        mobilesasa()
        _send(tenant)
        assert Notification.objects.get(recipient=tenant).status == Notification.Status.SENT

    def test_a_refused_message_is_recorded_as_failed(self, tenant, mobilesasa):
        mobilesasa(401, {"status": False, "message": "Invalid sender ID"})
        _send(tenant)
        assert Notification.objects.get(recipient=tenant).status == Notification.Status.FAILED

    def test_the_refusal_says_why(self, tenant, mobilesasa):
        mobilesasa(401, {"status": False, "message": "Invalid sender ID"})
        _send(tenant)
        assert "Invalid sender ID" in Notification.objects.get(recipient=tenant).error


class TestWhenMobileSasaCannotBeReached:
    def test_nothing_is_recorded_as_sent(self, tenant, monkeypatch, settings):
        settings.MOBILESASA_API_KEY = "key-123"

        def down(*args, **kwargs):
            raise requests.ConnectionError("unreachable")

        monkeypatch.setattr(tasks._requests, "post", down)
        _send(tenant)
        assert not Notification.objects.filter(recipient=tenant, status=Notification.Status.SENT).exists()


def _count_posts(monkeypatch, outcome):
    calls = []

    def post(url, json, headers, timeout):
        calls.append(json)
        return outcome()

    monkeypatch.setattr(tasks._requests, "post", post)
    return calls


class TestWhatIsTriedAgain:
    def test_a_rate_limited_send_is_tried_again(self, tenant, monkeypatch):
        calls = _count_posts(monkeypatch, lambda: _Reply(429, {"status": False}))
        _send(tenant)
        assert len(calls) == 5

    def test_after_the_last_try_it_is_recorded_as_not_sent(self, tenant, monkeypatch):
        _count_posts(monkeypatch, lambda: _Reply(503, {"status": False}))
        _send(tenant)
        assert Notification.objects.get(recipient=tenant).status == Notification.Status.FAILED

    def test_a_refusal_is_not_tried_again(self, tenant, monkeypatch):
        calls = _count_posts(monkeypatch, lambda: _Reply(
            422, {"status": False, "responseCode": "0422", "message": "Invalid phone"}))
        _send(tenant)
        assert len(calls) == 1

    def test_a_lost_reply_is_not_tried_again(self, tenant, monkeypatch):
        # It may already be queued: sending again could reach the tenant twice.
        def no_reply():
            raise requests.ReadTimeout("no reply")

        calls = _count_posts(monkeypatch, no_reply)
        _send(tenant)
        assert len(calls) == 1

    def test_a_lost_reply_says_it_may_have_gone(self, tenant, monkeypatch):
        def no_reply():
            raise requests.ReadTimeout("no reply")

        _count_posts(monkeypatch, no_reply)
        _send(tenant)
        assert "may still have been sent" in Notification.objects.get(recipient=tenant).error
