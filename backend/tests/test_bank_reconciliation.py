from django.utils import timezone

from apps.payments.bank_reconcile import reconcile_bank_notification
from apps.payments.models import BankPaymentNotification, Payment


def test_bank_payment_is_not_matched_by_amount_alone(db, invoice):
    notification = BankPaymentNotification.objects.create(
        bank=BankPaymentNotification.Bank.KCB,
        transaction_ref="KCB-UNRELATED-001",
        amount=invoice.amount_due,
        payment_ref="UNRELATED",
        credited_at=timezone.now(),
        raw_payload={},
    )

    matched = reconcile_bank_notification(notification)

    assert matched is False
    assert not Payment.objects.filter(bank_reference="KCB-UNRELATED-001").exists()


def test_transaction_reference_is_unique_per_bank(db):
    common = {
        "transaction_ref": "SHARED-REFERENCE-001",
        "amount": "1000.00",
        "credited_at": timezone.now(),
        "raw_payload": {},
    }
    BankPaymentNotification.objects.create(
        bank=BankPaymentNotification.Bank.KCB,
        **common,
    )

    BankPaymentNotification.objects.create(
        bank=BankPaymentNotification.Bank.EQUITY,
        **common,
    )

    assert BankPaymentNotification.objects.filter(
        transaction_ref="SHARED-REFERENCE-001"
    ).count() == 2
