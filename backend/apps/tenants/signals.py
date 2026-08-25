from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Tenancy
from apps.properties.models import Unit


@receiver(post_save, sender=Tenancy)
def sync_unit_status(sender, instance, **kwargs):
    """Keep Unit.status in sync whenever a Tenancy is saved."""
    unit = instance.unit
    if instance.status == Tenancy.Status.ACTIVE:
        if unit.status != Unit.Status.OCCUPIED:
            unit.status = Unit.Status.OCCUPIED
            unit.save(update_fields=["status"])
    elif instance.status in (Tenancy.Status.EXPIRED, Tenancy.Status.TERMINATED):
        # Only mark vacant if no other active tenancy exists for this unit
        has_active = Tenancy.objects.filter(
            unit=unit, status=Tenancy.Status.ACTIVE
        ).exclude(pk=instance.pk).exists()
        if not has_active and unit.status != Unit.Status.VACANT:
            unit.status = Unit.Status.VACANT
            unit.save(update_fields=["status"])
