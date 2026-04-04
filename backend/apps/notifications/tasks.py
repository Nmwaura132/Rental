import logging
import requests as _requests
from celery import shared_task
from django.conf import settings
from django.utils import timezone

logger = logging.getLogger(__name__)


def _get_sms_service():
    import africastalking
    africastalking.initialize(settings.AT_USERNAME, settings.AT_API_KEY)
    return africastalking.SMS


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def send_sms(self, recipient_id, message, phone_number=None):
    """Send an SMS via Africa's Talking. Logs result to Notification model."""
    from .models import Notification
    from django.contrib.auth import get_user_model

    User = get_user_model()

    try:
        user = User.objects.get(id=recipient_id)
        phone = phone_number or user.phone_number

        sms = _get_sms_service()
        response = sms.send(message, [phone], sender_id=settings.AT_SENDER_ID or None)

        success = response["SMSMessageData"]["Recipients"][0]["status"] == "Success"
        Notification.objects.create(
            recipient=user,
            channel=Notification.Channel.SMS,
            message=message,
            status=Notification.Status.SENT if success else Notification.Status.FAILED,
            sent_at=timezone.now() if success else None,
            error="" if success else str(response),
        )
        logger.info("SMS sent to %s: %s", phone, "OK" if success else "FAILED")

    except Exception as exc:
        logger.error("SMS failed for user %s: %s", recipient_id, exc)
        raise self.retry(exc=exc)


@shared_task
def send_payment_receipt_sms(payment_id):
    """Send a payment receipt SMS to the tenant after M-Pesa confirmation."""
    from apps.payments.models import Payment

    payment = Payment.objects.select_related(
        "invoice__lease__tenant", "invoice__lease__unit__property"
    ).get(id=payment_id)

    tenant = payment.invoice.lease.tenant
    unit = payment.invoice.lease.unit
    invoice = payment.invoice

    message = (
        f"Dear {tenant.first_name}, your payment of KES {payment.amount:,.0f} "
        f"for {unit.property.name} Unit {unit.unit_number} has been received. "
        f"Receipt: {payment.mpesa_receipt_number}. "
        f"Balance: KES {invoice.balance:,.0f}. Thank you!"
    )
    send_sms.delay(tenant.id, message)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def send_whatsapp(self, recipient_id, message, media_url=None):
    """
    Send a WhatsApp message via Africa's Talking.
    Only runs when WHATSAPP_ENABLED=true in settings.
    Falls back silently if WhatsApp is disabled.
    """
    if not getattr(settings, "WHATSAPP_ENABLED", False):
        logger.debug("WhatsApp disabled; skipping message for user %s", recipient_id)
        return

    from .models import Notification
    from django.contrib.auth import get_user_model

    User = get_user_model()

    try:
        user = User.objects.get(id=recipient_id)
        phone = user.phone_number

        payload = {
            "username": settings.AT_USERNAME,
            "to": phone,
            "message": message,
        }
        if media_url:
            payload["mediaUrl"] = media_url

        resp = _requests.post(
            "https://api.africastalking.com/version1/messaging/whatsapp/send",
            headers={
                "apiKey": settings.AT_API_KEY,
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data=payload,
            timeout=15,
        )
        success = resp.status_code == 201

        Notification.objects.create(
            recipient=user,
            channel=Notification.Channel.WHATSAPP
            if hasattr(Notification.Channel, "WHATSAPP")
            else Notification.Channel.SMS,
            message=message,
            status=Notification.Status.SENT if success else Notification.Status.FAILED,
            sent_at=timezone.now() if success else None,
            error="" if success else resp.text,
        )
        logger.info("WhatsApp to %s: %s", phone, "OK" if success else f"FAILED {resp.text}")

    except Exception as exc:
        logger.error("WhatsApp failed for user %s: %s", recipient_id, exc)
        raise self.retry(exc=exc)


@shared_task
def send_rent_reminders():
    """
    Celery Beat task — runs daily.
    Sends SMS reminders for invoices due in 7 days, 3 days, and today.
    """
    from apps.payments.models import Invoice
    from datetime import timedelta

    today = timezone.now().date()
    reminder_days = [7, 3, 0]

    for days in reminder_days:
        target_date = today + timedelta(days=days)
        invoices = Invoice.objects.filter(
            due_date=target_date,
            status__in=[Invoice.Status.PENDING, Invoice.Status.PARTIALLY_PAID],
        ).select_related("lease__tenant", "lease__unit__property")

        for invoice in invoices:
            tenant = invoice.lease.tenant
            unit = invoice.lease.unit
            balance = invoice.balance

            if days == 0:
                msg = (
                    f"Dear {tenant.first_name}, your rent of KES {balance:,.0f} "
                    f"for {unit.property.name} Unit {unit.unit_number} is due TODAY. "
                    f"Pay via M-Pesa Paybill {settings.MPESA_SHORTCODE}, Acc: {unit.unit_number}."
                )
            else:
                msg = (
                    f"Dear {tenant.first_name}, your rent of KES {balance:,.0f} "
                    f"for {unit.property.name} Unit {unit.unit_number} is due in {days} days. "
                    f"Pay via M-Pesa Paybill {settings.MPESA_SHORTCODE}, Acc: {unit.unit_number}."
                )

            send_sms.delay(tenant.id, msg)
