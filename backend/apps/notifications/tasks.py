import logging
import requests as _requests
from decimal import Decimal

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


@shared_task(bind=True, max_retries=5, default_retry_delay=5)
def send_payment_receipt_sms(self, payment_id):
    """Send a payment receipt SMS to the tenant after M-Pesa confirmation.

    Retries when the Payment row isn't visible yet (the caller's transaction
    may still be committing when this task dequeues) and on transient DB errors.
    """
    from apps.payments.models import Payment

    try:
        payment = Payment.objects.select_related(
            "invoice__tenancy__tenant", "invoice__tenancy__unit__property"
        ).get(id=payment_id)
    except Payment.DoesNotExist as exc:
        # WHY: parent transaction may not have committed before this task ran.
        logger.warning("Payment %s not yet visible — retrying.", payment_id)
        raise self.retry(exc=exc, countdown=5)

    tenant = payment.invoice.tenancy.tenant
    unit = payment.invoice.tenancy.unit
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


# Days before the due date to remind on, and days after it to chase on.
# Fixed offsets rather than "every day while unpaid" so a late tenant gets
# chased without being texted daily. The bill itself goes out when the invoice
# is raised on the 1st, so reminders only need the eve and the day.
REMINDER_DAYS_BEFORE = [1, 0]
CHASE_DAYS_AFTER = [3, 7, 14]

# WHY OVERDUE is included: mark_overdue_invoices runs at 00:05 and flips a late
# invoice out of PENDING, so a status filter of PENDING/PARTIALLY_PAID alone
# went silent from the morning after the due date onwards — reminders stopped
# exactly when the tenant had actually failed to pay.
_UNPAID = [
    "pending",
    "partially_paid",
    "overdue",
]


@shared_task
def send_rent_reminders():
    """Celery Beat task — runs daily.

    Reminds before rent is due, and keeps chasing after it falls late.

    WHY one message per tenancy rather than per invoice: a tenant three months
    behind used to get three texts on the same morning, each quoting one
    month's balance, none of them what they actually owed. The trigger is still
    an invoice reaching a reminder day; the message quotes everything unpaid.
    """
    from datetime import timedelta

    from apps.payments.models import Invoice
    from apps.payments.services import how_to_pay

    today = timezone.localdate()

    # Days relative to the due date, most overdue first, so a tenancy that hits
    # two triggers on one day is told about the more serious one.
    offsets = sorted(REMINDER_DAYS_BEFORE + [-d for d in CHASE_DAYS_AFTER])
    triggered = {}
    for days in offsets:
        for invoice in Invoice.objects.filter(
            due_date=today + timedelta(days=days), status__in=_UNPAID
        ).select_related("tenancy__tenant", "tenancy__unit__property"):
            triggered.setdefault(invoice.tenancy_id, (invoice.tenancy, days))

    for tenancy, days in triggered.values():
        unpaid = list(Invoice.objects.filter(tenancy=tenancy, status__in=_UNPAID))
        owed = sum((i.balance for i in unpaid), Decimal("0"))
        tenant, unit = tenancy.tenant, tenancy.unit
        where = f"{unit.property.name} Unit {unit.unit_number}"

        if days > 1:
            when = f"is due in {days} days"
        elif days == 1:
            when = "is due tomorrow"
        elif days == 0:
            when = "is due TODAY"
        else:
            when = f"is {-days} days overdue"

        others = (
            f" This includes {len(unpaid) - 1} other unpaid "
            f"{'bill' if len(unpaid) == 2 else 'bills'}."
            if len(unpaid) > 1 else ""
        )
        send_sms.delay(
            tenant.id,
            f"Dear {tenant.first_name}, your rent of KES {owed:,.0f} for {where} "
            f"{when}.{others} {how_to_pay(unit)}",
        )


@shared_task
def remind_missing_meter_readings():
    """Celery Beat task — runs on the 28th.

    Tells whoever reads the meters which occupied units have no reading yet
    for this month. A unit left unread is billed without its water on the 1st.
    Both the landlord and the caretaker are told, since either may read them.
    """
    from apps.properties.models import MeterReading, Property, PropertyCharge
    from apps.tenants.models import Tenancy

    period = timezone.localdate().replace(day=1)

    for property_ in Property.objects.filter(
        charges__is_active=True,
        charges__billing_method=PropertyCharge.BillingMethod.METERED,
    ).distinct():
        charges = property_.charges.filter(
            is_active=True, billing_method=PropertyCharge.BillingMethod.METERED
        )
        occupied = property_.units.filter(
            tenancies__status=Tenancy.Status.ACTIVE
        ).distinct().order_by("unit_number")

        missing = [
            unit.unit_number
            for unit in occupied
            if any(
                not MeterReading.objects.filter(unit=unit, charge=charge, period=period).exists()
                for charge in charges
            )
        ]
        if not missing:
            continue

        shown = ", ".join(missing[:8]) + (f" and {len(missing) - 8} more" if len(missing) > 8 else "")
        message = (
            f"{property_.name}: {len(missing)} unit{'s' if len(missing) != 1 else ''} "
            f"still {'have' if len(missing) != 1 else 'has'} no meter reading for "
            f"{period:%B} ({shown}). Enter them before the 1st so water is on the first bill."
        )
        for person_id in {property_.owner_id, property_.caretaker_id} - {None}:
            send_sms.delay(person_id, message)
