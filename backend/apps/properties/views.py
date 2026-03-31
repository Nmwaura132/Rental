from django.db import transaction
from rest_framework import viewsets, permissions
from django_filters.rest_framework import DjangoFilterBackend
from .models import Property, Unit, PropertyCharge
from .serializers import PropertySerializer, UnitSerializer, PropertyChargeSerializer


class PropertyViewSet(viewsets.ModelViewSet):
    serializer_class = PropertySerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["county", "town"]

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return Property.objects.filter(owner=user).prefetch_related("units")
        if user.is_caretaker:
            return Property.objects.filter(caretaker=user).prefetch_related("units")
        # Tenant: only the property of their active lease(s)
        return Property.objects.filter(
            units__leases__tenant=user,
            units__leases__status="active",
        ).distinct().prefetch_related("units")

    def perform_destroy(self, instance):
        """
        Delete in reverse-PROTECT order so FK constraints are satisfied:
        Payments → Invoices → MaintenanceRequests → Leases → (Units + Property via CASCADE)
        """
        from apps.tenants.models import Lease, MaintenanceRequest
        from apps.payments.models import Invoice, Payment

        with transaction.atomic():
            unit_ids = list(instance.units.values_list("id", flat=True))
            lease_ids = list(Lease.objects.filter(unit_id__in=unit_ids).values_list("id", flat=True))
            invoice_ids = list(Invoice.objects.filter(lease_id__in=lease_ids).values_list("id", flat=True))

            Payment.objects.filter(invoice_id__in=invoice_ids).delete()
            Invoice.objects.filter(id__in=invoice_ids).delete()
            MaintenanceRequest.objects.filter(lease_id__in=lease_ids).delete()
            Lease.objects.filter(id__in=lease_ids).delete()
            instance.delete()  # cascades to units


class PropertyChargeViewSet(viewsets.ModelViewSet):
    serializer_class = PropertyChargeSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["property", "charge_type", "is_active"]

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return PropertyCharge.objects.filter(property__owner=user).select_related("property")
        if user.is_caretaker:
            return PropertyCharge.objects.filter(property__caretaker=user).select_related("property")
        return PropertyCharge.objects.none()


class UnitViewSet(viewsets.ModelViewSet):
    serializer_class = UnitSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "unit_type", "property"]

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return Unit.objects.filter(property__owner=user).select_related("property")
        if user.is_caretaker:
            return Unit.objects.filter(property__caretaker=user).select_related("property")
        # Tenant: only their leased unit(s)
        return Unit.objects.filter(
            leases__tenant=user,
            leases__status="active",
        ).select_related("property").distinct()
