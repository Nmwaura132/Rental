"""A landlord's own ways of being paid, and payments routed by them.

Each landlord who signs up brings their own paybill. Tenants must be told to
pay that one, and money arriving on it must be credited only to that
landlord's tenants.
"""
from __future__ import annotations

import base64
import json
from decimal import Decimal

import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from apps.payments.models import BankPaymentNotification, Payment, PaymentAccount
from apps.payments.services import how_to_pay, pay_to, prompts_allowed
from apps.payments.tasks import process_bank_notification

User = get_user_model()

ACCOUNTS = "/api/v1/payments/accounts/"
KCB_IPN = "/api/v1/payments/bank/kcb/ipn/"


@pytest.fixture(autouse=True)
def reconcile_inline(monkeypatch):
    # WHY: the IPN hands matching to Celery; run it in-process so the test sees
    # where the money went.
    monkeypatch.setattr(process_bank_notification, "delay", lambda pk: process_bank_notification(pk))


def _client(user):
    api = APIClient()
    api.force_authenticate(user=user)
    return api


def _add(user, **fields):
    return _client(user).post(ACCOUNTS, fields, format="json")


def _kcb(landlord, number="522522", secret="s3cret", status=PaymentAccount.Status.ACTIVE, prefix=""):
    return PaymentAccount.objects.create(
        owner=landlord, kind=PaymentAccount.Kind.KCB_PAYBILL, number=number,
        account_prefix=prefix, status=status, ipn_secret=secret,
    )


# Stands in for KCB's signing key; settings get its public half, as they
# would get the one KCB issues.
KCB_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
IMPOSTOR_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture(autouse=True)
def kcb_public_key(settings):
    settings.KCB_IPN_PUBLIC_KEY = KCB_KEY.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode()


def _sign(raw: bytes, key=KCB_KEY) -> str:
    return base64.b64encode(key.sign(raw, padding.PKCS1v15(), hashes.SHA256())).decode()


def _notify(body: dict, key=KCB_KEY):
    raw = json.dumps(body).encode()
    return APIClient().post(KCB_IPN, data=raw, content_type="application/json", HTTP_SIGNATURE=_sign(raw, key))


def _payment(ref, amount="15000.00", shortcode="522522", trans_id="KCB001"):
    """A notification in the shape KCB's IPN Account specification gives."""
    return {
        "transactionReference": trans_id,
        "requestId": "c7d702cb-6b5f-4fa6-8b57-436d0f789017",
        "channelCode": "202",
        "timestamp": "20261020120000",
        "transactionAmount": amount,
        "currency": "KES",
        "customerReference": ref,
        "customerName": "Achieng Otieno",
        "customerMobileNumber": "254711000000",
        "balance": "",
        "narration": "Rent",
        "creditAccountIdentifier": "8154415",
        "organizationShortCode": shortcode,
        "tillNumber": "",
    }


@pytest.fixture
def other_landlord(db):
    return User.objects.create_user(
        phone_number="+254700222000", password="Other@Test1",
        first_name="Other", last_name="Landlord", role=User.Role.LANDLORD,
    )


# ── Setting them up ──────────────────────────────────────────────────────────


class TestAddingAPaymentMethod:
    def test_a_kcb_paybill_waits_to_be_connected(self, landlord):
        response = _add(landlord, kind="kcb_paybill", number="522522")
        assert response.data["status"] == "connecting"

    def test_a_manual_paybill_is_ready_at_once(self, landlord):
        response = _add(landlord, kind="paybill", number="899790", account_prefix="623943#")
        assert response.data["status"] == "active"

    def test_the_kcb_secret_is_never_sent_to_the_app(self, landlord):
        _kcb(landlord)
        rows = _client(landlord).get(ACCOUNTS).data["results"]
        assert "ipn_secret" not in rows[0]

    def test_the_status_cannot_be_set_by_the_landlord(self, landlord):
        response = _add(landlord, kind="kcb_paybill", number="522522", status="active")
        assert response.data["status"] == "connecting"

    def test_a_landlord_sees_only_their_own(self, landlord, other_landlord):
        _kcb(other_landlord)
        assert _client(landlord).get(ACCOUNTS).data["results"] == []

    def test_a_tenant_cannot_add_one(self, tenant):
        assert _add(tenant, kind="cash").status_code == 403

    def test_a_caretaker_cannot_add_one(self, caretaker):
        assert _add(caretaker, kind="cash").status_code == 403


class TestWhatAMethodNeeds:
    def test_a_paybill_needs_its_number(self, landlord):
        assert "number" in _add(landlord, kind="paybill", number="12ab").data

    def test_a_till_has_no_account_number(self, landlord):
        response = _add(landlord, kind="till", number="123456", account_prefix="X#")
        assert "account_prefix" in response.data

    def test_a_bank_account_needs_its_number(self, landlord):
        response = _add(landlord, kind="bank", bank_name="KCB", account_name="J Doe")
        assert "account_number" in response.data

    def test_cash_is_set_up_once(self, landlord):
        _add(landlord, kind="cash")
        assert _add(landlord, kind="cash").status_code == 400

    def test_one_kcb_paybill_belongs_to_one_landlord(self, landlord, other_landlord):
        _kcb(other_landlord)
        assert "number" in _add(landlord, kind="kcb_paybill", number="522522").data

    def test_the_database_refuses_a_second_claim_on_a_kcb_paybill(self, landlord, other_landlord):
        # Not just the API: admin or a race between two sign-ups must not get
        # past it either.
        from django.db import IntegrityError, transaction

        _kcb(other_landlord)
        with pytest.raises(IntegrityError), transaction.atomic():
            _kcb(landlord)

    def test_two_landlords_can_share_a_bank_paybill(self, landlord, other_landlord):
        _add(other_landlord, kind="paybill", number="899790", account_prefix="111#")
        response = _add(landlord, kind="paybill", number="899790", account_prefix="623943#")
        assert response.status_code == 201


class TestChangingAPaybill:
    def test_a_new_kcb_number_must_be_connected_again(self, landlord):
        account = _kcb(landlord)
        _client(landlord).patch(f"{ACCOUNTS}{account.id}/", {"number": "600100"}, format="json")
        account.refresh_from_db()
        assert account.status == PaymentAccount.Status.CONNECTING

    def test_a_new_kcb_number_drops_the_old_secret(self, landlord):
        account = _kcb(landlord)
        _client(landlord).patch(f"{ACCOUNTS}{account.id}/", {"number": "600100"}, format="json")
        account.refresh_from_db()
        assert account.ipn_secret == ""


# ── What tenants are told ────────────────────────────────────────────────────


class TestWhereTenantsArePointed:
    def test_the_landlords_own_paybill_is_named(self, landlord, unit):
        _kcb(landlord, prefix="")
        assert pay_to(unit) == ("522522", "A1")

    def test_the_account_prefix_goes_before_the_house(self, landlord, unit):
        PaymentAccount.objects.create(
            owner=landlord, kind=PaymentAccount.Kind.PAYBILL, number="899790", account_prefix="623943#"
        )
        assert pay_to(unit) == ("899790", "623943#A1")

    def test_a_till_is_paid_without_an_account(self, landlord, unit):
        PaymentAccount.objects.create(owner=landlord, kind=PaymentAccount.Kind.TILL, number="123456")
        assert how_to_pay(unit) == "Pay via M-Pesa Till 123456."

    def test_without_one_the_platform_paybill_is_named(self, unit, settings):
        settings.RENT_PAYBILL = "174379"
        settings.RENT_ACCOUNT_PREFIX = ""
        assert pay_to(unit) == ("174379", unit.payment_code)

    def test_a_landlords_own_paybill_switches_prompts_off(self, landlord, unit, settings):
        # The prompt goes through the platform's shortcode, so it would pay the
        # platform, not the landlord.
        settings.STK_PUSH_ENABLED = True
        _kcb(landlord)
        assert prompts_allowed(unit) is False

    def test_a_prompt_is_refused_for_that_landlords_tenant(self, landlord, tenant, invoice, settings):
        settings.STK_PUSH_ENABLED = True
        _kcb(landlord)
        response = _client(tenant).post("/api/v1/payments/stk/push/", {"invoice_id": invoice.id})
        assert response.status_code == 400

    def test_the_tenant_is_shown_the_landlords_bank(self, landlord, tenant, tenancy):
        PaymentAccount.objects.create(
            owner=landlord, kind=PaymentAccount.Kind.BANK, bank_name="KCB",
            account_name="Test Landlord", account_number="1234567890",
        )
        home = _client(tenant).get("/api/v1/payments/dashboard/").data
        assert home["bank_accounts"][0]["account_number"] == "1234567890"


# ── Money arriving on a landlord's KCB paybill ───────────────────────────────


class TestKCBPaymentsRoutedByPaybill:
    def test_a_notification_signed_by_kcb_is_accepted(self, landlord, invoice):
        _kcb(landlord)
        assert _notify(_payment("A1")).status_code == 200

    def test_kcb_is_told_it_was_received(self, landlord, invoice):
        _kcb(landlord)
        assert _notify(_payment("A1")).data == {
            "transactionID": "KCB001", "statusCode": "0", "statusMessage": "Notification received",
        }

    def test_a_notification_signed_by_anyone_else_is_refused(self, landlord, invoice):
        _kcb(landlord)
        assert _notify(_payment("A1"), key=IMPOSTOR_KEY).status_code == 403

    def test_a_forged_one_records_nothing(self, landlord, invoice):
        _kcb(landlord)
        _notify(_payment("A1"), key=IMPOSTOR_KEY)
        assert not BankPaymentNotification.objects.exists()

    def test_a_signed_body_changed_on_the_way_is_refused(self, landlord, invoice):
        _kcb(landlord)
        raw = json.dumps(_payment("A1")).encode()
        signature = _sign(raw)
        tampered = raw.replace(b"15000.00", b"95000.00")
        response = APIClient().post(KCB_IPN, data=tampered, content_type="application/json", HTTP_SIGNATURE=signature)
        assert response.status_code == 403

    def test_an_unsigned_one_is_refused(self, landlord, invoice):
        _kcb(landlord)
        response = APIClient().post(KCB_IPN, data=_payment("A1"), format="json")
        assert response.status_code == 403

    def test_without_kcbs_key_configured_everything_is_refused(self, landlord, invoice, settings):
        settings.KCB_IPN_PUBLIC_KEY = ""
        _kcb(landlord)
        assert _notify(_payment("A1")).status_code == 403

    def test_a_resent_notification_is_recorded_once(self, landlord, invoice):
        _kcb(landlord)
        _notify(_payment("A1"))
        _notify(_payment("A1"))
        assert Payment.objects.filter(bank_reference="KCB001").count() == 1

    def test_kcbs_time_is_read_as_nairobi_time(self, landlord, invoice):
        _kcb(landlord)
        _notify(_payment("rent"))
        held = BankPaymentNotification.objects.get(transaction_ref="KCB001")
        assert held.credited_at.isoformat() == "2026-10-20T09:00:00+00:00"

    def test_a_zero_amount_is_refused(self, landlord, invoice):
        _kcb(landlord)
        assert _notify(_payment("A1", amount="0.00")).status_code == 400

    def test_it_is_recorded_against_the_tenant(self, landlord, invoice):
        _kcb(landlord)
        _notify(_payment("A1"))
        assert Payment.objects.filter(invoice=invoice, bank_reference="KCB001").exists()

    def test_a_house_number_another_landlord_also_uses_still_matches(
        self, landlord, other_landlord, invoice
    ):
        from apps.properties.models import Property, Unit

        elsewhere = Property.objects.create(owner=other_landlord, name="Elsewhere")
        Unit.objects.create(
            property=elsewhere, unit_number="A1", rent_amount=Decimal("9000"), deposit_amount=Decimal("9000")
        )
        _kcb(landlord)
        _notify(_payment("A1"))
        assert Payment.objects.filter(invoice=invoice).exists()

    def test_the_full_account_number_typed_still_matches(self, landlord, invoice):
        _kcb(landlord, prefix="623943#")
        _notify(_payment("623943#A1"))
        assert Payment.objects.filter(invoice=invoice).exists()

    def test_it_never_pays_another_landlords_bill(self, landlord, other_landlord, invoice):
        _kcb(other_landlord)
        _notify(_payment(invoice.invoice_number))
        assert not Payment.objects.filter(invoice=invoice).exists()

    def test_money_on_a_paybill_still_connecting_is_not_credited(self, landlord, invoice):
        # Until staff confirm it is this landlord's, it is held for no one.
        _kcb(landlord, status=PaymentAccount.Status.CONNECTING)
        _notify(_payment("A1"))
        assert not Payment.objects.filter(invoice=invoice).exists()


class TestADepositWithNoHouseNumber:
    """A tenant who pays at a branch or by transfer often types nothing useful."""

    def test_it_is_held_for_the_landlord_to_assign(self, landlord, invoice):
        _kcb(landlord)
        _notify(_payment("rent oct"))
        held = BankPaymentNotification.objects.get(transaction_ref="KCB001")
        assert held.owner == landlord

    def test_it_is_not_recorded_against_anyone(self, landlord, invoice):
        _kcb(landlord)
        _notify(_payment("rent oct"))
        assert not Payment.objects.filter(bank_reference="KCB001").exists()

    def test_the_landlord_sees_it_waiting(self, landlord, invoice):
        _kcb(landlord)
        _notify(_payment("rent oct"))
        rows = _client(landlord).get("/api/v1/payments/bank/notifications/").data["results"]
        assert [r["transaction_ref"] for r in rows] == ["KCB001"]

    def test_another_landlord_does_not(self, landlord, other_landlord, invoice):
        _kcb(landlord)
        _notify(_payment("rent oct"))
        rows = _client(other_landlord).get("/api/v1/payments/bank/notifications/").data["results"]
        assert rows == []


class TestKCBsOwnSample:
    """The sample from KCB's IPN Account specification, byte for byte."""

    SAMPLE = (
        b'{\n "transactionReference": "FT00026252",\n'
        b' "requestId": "c7d702cb-6b5f-4fa6-8b57-436d0f789017",\n "channelCode": "202",\n'
        b' "timestamp": "2021111103005",\n "transactionAmount": "100.00",\n "currency": "KES",\n'
        b' "customerReference": "INV-0001",\n "customerName": "John Doe",\n'
        b' "customerMobileNumber": "25471111111",\n "balance": "",\n'
        b' "narration": "Payment for goods",\n "creditAccountIdentifier": "JD001",\n'
        b' "organizationShortCode": "777777",\n "tillNumber": "150150"\n}'
    )

    def _send(self):
        return APIClient().post(
            KCB_IPN, data=self.SAMPLE, content_type="application/json", HTTP_SIGNATURE=_sign(self.SAMPLE)
        )

    def test_it_is_acknowledged_as_kcb_expects(self, db):
        assert self._send().data == {
            "transactionID": "FT00026252", "statusCode": "0", "statusMessage": "Notification received",
        }

    def test_its_amount_is_kept(self, db):
        self._send()
        assert BankPaymentNotification.objects.get().amount == Decimal("100.00")
