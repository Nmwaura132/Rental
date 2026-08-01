from django_filters.rest_framework import DjangoFilterBackend
from django.db.models.deletion import ProtectedError
from rest_framework import permissions, viewsets
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from apps.core.permissions import IsLandlord

from .models import Property, PropertyCharge, Unit
from .serializers import PropertyChargeSerializer, PropertySerializer, UnitSerializer


def _validate_managed_property(user, property_):
    if user.is_landlord and property_.owner_id == user.id:
        return
    if user.is_caretaker and property_.caretaker_id == user.id:
        return
    raise PermissionDenied("You cannot manage resources for this property.")


class PropertyViewSet(viewsets.ModelViewSet):
    serializer_class = PropertySerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["county", "town"]
    # WHY: drf-spectacular introspects with AnonymousUser. Setting an empty queryset
    # at class level lets it derive the model without invoking get_queryset().
    queryset = Property.objects.none()

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy"}:
            return [IsLandlord()]
        return super().get_permissions()

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return Property.objects.filter(owner=user).prefetch_related("units")
        if user.is_caretaker:
            return Property.objects.filter(caretaker=user).prefetch_related("units")
        return (
            Property.objects.filter(
                units__leases__tenant=user,
                units__leases__status="active",
            )
            .distinct()
            .prefetch_related("units")
        )

    def destroy(self, request, *args, **kwargs):
        try:
            return super().destroy(request, *args, **kwargs)
        except ProtectedError:
            return Response(
                {"error": "Properties with lease history cannot be deleted."},
                status=409,
            )


class PropertyChargeViewSet(viewsets.ModelViewSet):
    serializer_class = PropertyChargeSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["property", "charge_type", "is_active"]
    queryset = PropertyCharge.objects.none()

    def get_permissions(self):
        if self.action not in {"list", "retrieve"}:
            return [IsLandlord()]
        return super().get_permissions()

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return PropertyCharge.objects.filter(property__owner=user).select_related("property")
        if user.is_caretaker:
            return PropertyCharge.objects.filter(property__caretaker=user).select_related("property")
        return PropertyCharge.objects.none()

    def perform_create(self, serializer):
        _validate_managed_property(self.request.user, serializer.validated_data["property"])
        serializer.save()

    def perform_update(self, serializer):
        property_ = serializer.validated_data.get("property", serializer.instance.property)
        _validate_managed_property(self.request.user, property_)
        serializer.save()


class UnitViewSet(viewsets.ModelViewSet):
    serializer_class = UnitSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "unit_type", "property"]
    queryset = Unit.objects.none()

    def get_permissions(self):
        if self.action not in {"list", "retrieve"}:
            return [IsLandlord()]
        return super().get_permissions()

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return Unit.objects.filter(property__owner=user).select_related("property")
        if user.is_caretaker:
            return Unit.objects.filter(property__caretaker=user).select_related("property")
        return (
            Unit.objects.filter(
                leases__tenant=user,
                leases__status="active",
            )
            .select_related("property")
            .distinct()
        )

    def perform_create(self, serializer):
        _validate_managed_property(self.request.user, serializer.validated_data["property"])
        serializer.save()

    def perform_update(self, serializer):
        property_ = serializer.validated_data.get("property", serializer.instance.property)
        _validate_managed_property(self.request.user, property_)
        serializer.save()

    def destroy(self, request, *args, **kwargs):
        try:
            return super().destroy(request, *args, **kwargs)
        except ProtectedError:
            return Response(
                {"error": "Units with lease history cannot be deleted."},
                status=409,
            )
