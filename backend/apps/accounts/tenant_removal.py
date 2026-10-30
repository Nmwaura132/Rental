"""Deleting a tenant from a landlord's records, and everything kept about them.

WHY this is allowed at all: a landlord entering tenants makes mistakes (a
wrong number, a test entry, someone who never moved in), and a record they
cannot remove keeps texting and billing a stranger. WHY payments from outside
block it: money that arrived by M-Pesa or a bank notification is a record of a
real transfer, which must not vanish with a tap; hand-entered payments and
deposits applied to bills are the landlord's own entries.
"""
from decimal import Decimal

from django.db import transaction
from django.db.models import Q, Sum


def _tenancies(tenant):
    from apps.tenants.models import Tenancy

    return Tenancy.objects.filter(tenant=tenant)


def _payments(tenant):
    from apps.payments.models import Payment

    return Payment.objects.filter(invoice__tenancy__tenant=tenant)


def _external(payments):
    """Payments that came from outside Kasa: not typed in by the landlord,
    and not the tenant's own deposit applied to a bill."""
    from apps.payments.models import Payment

    return payments.filter(recorded_by__isnull=True).exclude(method=Payment.Method.DEPOSIT)


def belongs_to(tenant, landlord) -> bool:
    """Only a tenant the landlord added, or who has lived in their houses, and
    never one who also rents from someone else."""
    tenancies = _tenancies(tenant)
    if tenancies.exclude(unit__property__owner=landlord).exists():
        return False
    return tenant.created_by_id == landlord.id or tenancies.exists()


def summary(tenant) -> dict:
    """What deleting this tenant would remove, for the landlord to confirm."""
    from apps.payments.models import Invoice

    payments = _payments(tenant)
    blocked = _external(payments).exists()
    return {
        "name": tenant.get_full_name(),
        "houses": sorted({t.unit.unit_number for t in _tenancies(tenant).select_related("unit")}),
        "bills": Invoice.objects.filter(tenancy__tenant=tenant).count(),
        "payments": payments.count(),
        "paid": payments.aggregate(total=Sum("amount"))["total"] or Decimal("0"),
        "can_delete": not blocked,
        "reason": (
            "This tenant has M-Pesa or bank payments on record, which cannot be deleted. "
            "Give notice to end their tenancy instead."
            if blocked else ""
        ),
    }


def remove(tenant) -> None:
    """Delete the tenant and everything kept about them, freeing their houses.

    Children before parents, since bills, payments, credits and settlements
    are protected from being deleted out from under each other.
    """
    from apps.payments.models import Invoice, TenancyCredit
    from apps.properties.models import Unit
    from apps.tenants.models import DepositSettlement, MaintenanceNote, Tenancy

    with transaction.atomic():
        tenancies = list(_tenancies(tenant).select_for_update())
        units = {t.unit_id for t in tenancies}
        TenancyCredit.objects.filter(tenancy__in=tenancies).delete()
        # A queryset delete, which skips Payment.delete()'s refusal to delete a
        # confirmed payment. Deliberate: summary() has already refused any
        # tenant with outside money, so only the landlord's own entries remain.
        if _external(_payments(tenant)).exists():
            raise ValueError("Refusing to delete payments that came from outside Kasa.")
        _payments(tenant).delete()
        DepositSettlement.objects.filter(tenancy__in=tenancies).delete()
        Invoice.objects.filter(tenancy__in=tenancies).delete()
        MaintenanceNote.objects.filter(Q(author=tenant) | Q(request__tenancy__in=tenancies)).delete()
        Tenancy.objects.filter(pk__in=[t.pk for t in tenancies]).delete()
        for unit in Unit.objects.filter(pk__in=units):
            if not unit.tenancies.filter(status=Tenancy.Status.ACTIVE).exists():
                unit.status = Unit.Status.VACANT
                unit.save(update_fields=["status"])
        tenant.delete()
