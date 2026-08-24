"""Reconcile bank notifications only from an exact invoice or unit reference."""

import logging

from django.db import transaction

logger = logging.getLogger(__name__)


def reconcile_bank_notification(notification, *, invoice_id=None) -> bool:
    from apps.tenants.models import Lease

    from .models import BankPaymentNotification, Invoice, Payment
    from .services import apply_confirmed_payment

    if notification.status == BankPaymentNotification.Status.MATCHED:
        return True

    reference = (notification.payment_ref or "").strip().upper()
    open_statuses = [
        Invoice.Status.PENDING,
        Invoice.Status.OVERDUE,
        Invoice.Status.PARTIALLY_PAID,
    ]
    invoice = None

    if invoice_id is not None:
        invoice = Invoice.objects.filter(
            pk=invoice_id,
            status__in=open_statuses,
        ).first()
    elif reference:
        invoice = Invoice.objects.filter(
            invoice_number__iexact=reference,
            status__in=open_statuses,
        ).first()

    if not invoice and invoice_id is None and reference:
        from apps.properties.models import Unit
        unit = Unit.match_reference(reference)
        lease = Lease.objects.filter(
            unit=unit,
            status=Lease.Status.ACTIVE,
        ).first() if unit else None
        if lease:
            invoice = Invoice.objects.filter(
                lease=lease,
                status__in=open_statuses,
            ).order_by("due_date").first()

    if not invoice:
        logger.info(
            "Bank notification %s (%s) has no exact invoice or unit match.",
            notification.transaction_ref,
            notification.bank,
        )
        return False

    with transaction.atomic():
        notification = BankPaymentNotification.objects.select_for_update().get(
            pk=notification.pk
        )
        if notification.status == BankPaymentNotification.Status.MATCHED:
            return True

        payment, _ = apply_confirmed_payment(
            invoice_id=invoice.pk,
            method=Payment.Method.BANK,
            amount=notification.amount,
            idempotency_key=(
                f"bank:{notification.bank}:{notification.transaction_ref}"
            ),
            paid_at=notification.credited_at,
            payment_fields={
                "bank_name": notification.get_bank_display(),
                "bank_account": notification.payer_account or None,
                "bank_reference": notification.transaction_ref,
            },
        )
        notification.status = BankPaymentNotification.Status.MATCHED
        notification.payment = payment
        notification.save(update_fields=["status", "payment"])

        def after_commit():
            from django.core.cache import cache
            from apps.notifications.tasks import send_payment_receipt_sms

            cache.delete(f"dashboard:{invoice.lease.tenant_id}")
            cache.delete(f"dashboard:{invoice.lease.unit.property.owner_id}")
            send_payment_receipt_sms.delay(payment.id)

        transaction.on_commit(after_commit)

    logger.info(
        "Bank notification %s matched invoice %s (KES %s).",
        notification.transaction_ref,
        invoice.invoice_number,
        notification.amount,
    )
    return True
