from rest_framework import viewsets, permissions
from django_filters.rest_framework import DjangoFilterBackend
from .models import Lease, MaintenanceRequest
from .serializers import LeaseSerializer, MaintenanceRequestSerializer


class LeaseViewSet(viewsets.ModelViewSet):
    serializer_class = LeaseSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "tenant", "unit"]

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return Lease.objects.filter(
                unit__property__owner=user
            ).select_related("tenant", "unit", "unit__property")
        if user.is_caretaker:
            return Lease.objects.filter(
                unit__property__caretaker=user
            ).select_related("tenant", "unit", "unit__property")
        # Tenant sees their own leases
        return Lease.objects.filter(tenant=user).select_related("unit", "unit__property")


class MaintenanceRequestViewSet(viewsets.ModelViewSet):
    serializer_class = MaintenanceRequestSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "priority"]

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return MaintenanceRequest.objects.filter(
                lease__unit__property__owner=user
            ).select_related("lease__tenant", "lease__unit")
        if user.is_caretaker:
            return MaintenanceRequest.objects.filter(
                lease__unit__property__caretaker=user
            ).select_related("lease__tenant", "lease__unit")
        return MaintenanceRequest.objects.filter(lease__tenant=user)
