from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Lease
from apps.properties.models import Unit


@receiver(post_save, sender=Lease)
def sync_unit_status(sender, instance, **kwargs):
    """Keep Unit.status in sync whenever a Lease is saved."""
    unit = instance.unit
    if instance.status == Lease.Status.ACTIVE:
        if unit.status != Unit.Status.OCCUPIED:
            unit.status = Unit.Status.OCCUPIED
            unit.save(update_fields=["status"])
    elif instance.status in (Lease.Status.EXPIRED, Lease.Status.TERMINATED):
        # Only mark vacant if no other active lease exists for this unit
        has_active = Lease.objects.filter(
            unit=unit, status=Lease.Status.ACTIVE
        ).exclude(pk=instance.pk).exists()
        if not has_active and unit.status != Unit.Status.VACANT:
            unit.status = Unit.Status.VACANT
            unit.save(update_fields=["status"])
