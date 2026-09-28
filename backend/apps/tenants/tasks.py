import logging

from celery import shared_task
from django.utils import timezone

from apps.notifications.tasks import send_sms

from .models import Tenancy

logger = logging.getLogger(__name__)


@shared_task
def end_expired_tenancies():
    """Celery Beat task — runs just after midnight.

    Ends every tenancy whose notice ran out yesterday or earlier. The tenant
    may occupy the unit through the whole of the effective date, so a tenancy
    only ends once that date is behind us. Saving it as terminated is what
    marks the unit vacant, through the signal that keeps the two in step.

    Billing does not depend on this having run: the monthly bill skips a
    tenancy whose notice has expired, so a missed night here cannot bill
    someone who has left.
    """
    today = timezone.localdate()
    ended = 0

    for tenancy in Tenancy.objects.filter(
        status=Tenancy.Status.ACTIVE, notice_effective_date__lt=today
    ).select_related("tenant", "unit__property"):
        tenancy.status = Tenancy.Status.TERMINATED
        tenancy.end_date = tenancy.notice_effective_date
        tenancy.save(update_fields=["status", "end_date"])
        ended += 1

        unit = tenancy.unit
        send_sms.delay(
            unit.property.owner_id,
            f"{tenancy.tenant.first_name} {tenancy.tenant.last_name} has moved out of "
            f"{unit.property.name} unit {unit.unit_number}. The tenancy has ended and "
            f"the unit is now vacant.",
        )

    logger.info("Ended %d tenancies whose notice had run out.", ended)
    return ended
