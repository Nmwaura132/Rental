from django_filters.rest_framework import DjangoFilterBackend
from django.db.models.deletion import ProtectedError
from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from apps.core.permissions import IsLandlord

# Imported inside the module rather than at call time: these are read-only
# lookups for the unit screen, and the apps are already coupled through
# Tenancy -> Unit.
from apps.payments.models import Payment
from apps.tenants.models import MaintenanceRequest, Tenancy

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
                units__tenancies__tenant=user,
                units__tenancies__status="active",
            )
            .distinct()
            .prefetch_related("units")
        )

    def destroy(self, request, *args, **kwargs):
        try:
            return super().destroy(request, *args, **kwargs)
        except ProtectedError:
            return Response(
                {"error": "Properties with tenancy history cannot be deleted."},
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
        # "occupancy" is a read, and knowing who lives in a unit is a
        # caretaker's actual job — the identity fields inside it are gated
        # separately, on ownership.
        if self.action not in {"list", "retrieve", "occupancy"}:
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
                tenancies__tenant=user,
                tenancies__status="active",
            )
            .select_related("property")
            .distinct()
        )

    @action(detail=True, methods=["get"], url_path="occupancy")
    def occupancy(self, request, pk=None):
        """Everything the unit screen shows, in one call.

        WHY one endpoint rather than composing on the client: payments and
        maintenance cannot currently be filtered to a tenancy, and opening those
        filters up would make it possible to walk another landlord's records.
        Assembling here keeps the scoping in one place — the unit is already
        restricted to what the caller manages by get_queryset.
        """
        unit = self.get_object()
        tenancy = (
            Tenancy.objects.filter(unit=unit, status=Tenancy.Status.ACTIVE)
            .select_related("tenant")
            .order_by("-start_date")
            .first()
        )

        payload = {
            "unit": UnitSerializer(unit).data,
            "property_name": unit.property.name,
            "tenancy": None,
            "tenant": None,
            "payments": [],
            "maintenance": [],
        }

        if tenancy is None:
            return Response(payload)

        # WHY the identity fields are owner-only: a caretaker manages occupancy,
        # not the landlord's tax filing, and a national ID plus KRA PIN together
        # are the pair used for identity fraud.
        is_owner = unit.property.owner_id == request.user.id
        tenant = tenancy.tenant

        payload["tenancy"] = {
            "id": tenancy.id,
            "start_date": tenancy.start_date,
            "end_date": tenancy.end_date,
            "rent_amount": tenancy.rent_amount,
            "deposit_amount": tenancy.deposit_amount,
            "deposit_paid": tenancy.deposit_paid,
            "status": tenancy.status,
            "notice_given_at": tenancy.notice_given_at,
            "notice_effective_date": tenancy.notice_effective_date,
        }
        payload["tenant"] = {
            "id": tenant.id,
            "name": f"{tenant.first_name} {tenant.last_name}".strip(),
            "phone_number": tenant.phone_number,
            "occupation": tenant.occupation,
            "next_of_kin_name": tenant.next_of_kin_name,
            "next_of_kin_phone": tenant.next_of_kin_phone,
            **(
                {"kra_pin": tenant.kra_pin, "national_id": tenant.national_id}
                if is_owner
                else {}
            ),
        }

        payments = (
            Payment.objects.filter(
                invoice__tenancy=tenancy, status=Payment.Status.CONFIRMED
            )
            .select_related("invoice")
            .order_by("-paid_at")[:20]
        )
        payload["payments"] = [
            {
                "id": p.id,
                "amount": p.amount,
                "method": p.method,
                "paid_at": p.paid_at,
                "invoice_number": p.invoice.invoice_number,
            }
            for p in payments
        ]

        requests = MaintenanceRequest.objects.filter(tenancy=tenancy).order_by(
            "-created_at"
        )[:20]
        payload["maintenance"] = [
            {
                "id": m.id,
                "title": m.title,
                "status": m.status,
                "priority": m.priority,
                "created_at": m.created_at,
            }
            for m in requests
        ]

        return Response(payload)

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
                {"error": "Units with tenancy history cannot be deleted."},
                status=409,
            )
