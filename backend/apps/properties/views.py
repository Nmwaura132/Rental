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

from .models import MeterReading, Property, PropertyCharge, Unit
from .serializers import (
    MeterReadingSerializer,
    PropertyChargeSerializer,
    PropertySerializer,
    UnitSerializer,
)


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
        if self.action in {"create", "update", "partial_update", "destroy", "renumber"}:
            return [IsLandlord()]
        return super().get_permissions()

    @action(detail=True, methods=["post"])
    def renumber(self, request, pk=None):
        """Give a property's units new house numbers in one step.

        Body: {"units": [{"id": 1, "unit_number": "G1", "floor": 0}, ...]}

        WHY all at once, on the server: renaming units one by one fails as soon
        as two of them trade numbers ("1A" <-> "1B"), because each rename
        briefly collides with the other. Everything is cleared to a placeholder
        first, then written, inside one transaction — all or nothing.
        """
        from django.db import transaction

        property_ = self.get_object()
        entries = request.data.get("units") or []
        units = {u.id: u for u in property_.units.all()}

        seen = {}
        for entry in entries:
            number = str(entry.get("unit_number") or "").strip()
            unit_id = entry.get("id")
            if unit_id not in units:
                return Response({"error": f"Unit {unit_id} is not in this property."}, status=400)
            if not number:
                return Response({"error": f"Unit {units[unit_id].unit_number} needs a number."}, status=400)
            if len(number) > 20:
                return Response({"error": f"{number} is longer than 20 characters."}, status=400)
            if number.upper() in seen:
                return Response({"error": f"{number} is used twice."}, status=400)
            floor = entry.get("floor")
            if floor is not None and (not isinstance(floor, int) or floor < 0):
                return Response({"error": f"Floor for {number} must be 0 or more."}, status=400)
            seen[number.upper()] = unit_id

        # Units left out keep their numbers, so the new ones must not clash with them.
        untouched = {u.unit_number.upper() for uid, u in units.items() if uid not in {e["id"] for e in entries}}
        clash = untouched & set(seen)
        if clash:
            return Response({"error": f"{sorted(clash)[0]} already belongs to another unit."}, status=400)

        with transaction.atomic():
            ids = [e["id"] for e in entries]
            # Placeholders are unique per unit, so no step can collide. The
            # payment code is cleared too, so a unit taking "G1" is not pushed
            # onto "G1XXXX" by a neighbour still holding the old "G1" code.
            for unit_id in ids:
                Unit.objects.filter(pk=unit_id).update(
                    unit_number=f"~{unit_id}", payment_code=f"~{unit_id}"[:12]
                )
            for entry in entries:
                unit = Unit.objects.get(pk=entry["id"])
                unit.unit_number = str(entry["unit_number"]).strip()
                if entry.get("floor") is not None:
                    unit.floor = int(entry["floor"])
                unit.save()

        return Response(UnitSerializer(property_.units.order_by("floor", "unit_number"), many=True).data)

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

        from apps.payments.services import pay_to

        paybill, pay_account = pay_to(unit)
        payload = {
            "unit": UnitSerializer(unit).data,
            "property_name": unit.property.name,
            # What the tenant types into M-Pesa for this unit, so the landlord
            # can read it out when a payment does not arrive where expected.
            "paybill": paybill,
            "pay_account": pay_account,
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
            "status": tenancy.status,
            "notice_given_at": tenancy.notice_given_at,
            "notice_effective_date": tenancy.notice_effective_date,
        }
        if is_owner:
            from decimal import Decimal

            from apps.payments.models import Invoice

            open_bills = Invoice.objects.filter(
                tenancy=tenancy,
                status__in=[
                    Invoice.Status.PENDING, Invoice.Status.PARTIALLY_PAID, Invoice.Status.OVERDUE,
                ],
            )
            # WHY these are owner-only: the deposit and what the tenant owes are
            # the landlord's business. A caretaker looks after the building.
            payload["tenancy"]["deposit_amount"] = tenancy.deposit_amount
            payload["tenancy"]["deposit_paid"] = tenancy.deposit_paid
            payload["tenancy"]["balance"] = sum((b.balance for b in open_bills), Decimal("0"))
            payload["tenancy"]["overdue"] = open_bills.filter(status=Invoice.Status.OVERDUE).exists()
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

        if is_owner:
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
                    "method_display": p.get_method_display(),
                    "paid_at": p.paid_at,
                    "invoice_number": p.invoice.invoice_number,
                    "reference": p.mpesa_receipt_number or p.bank_reference or "",
                    "period_start": p.invoice.period_start,
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
                "resolved_at": m.resolved_at,
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


class MeterReadingViewSet(viewsets.ModelViewSet):
    """Meter readings, entered by the landlord or the caretaker."""

    serializer_class = MeterReadingSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["unit", "charge", "period"]
    queryset = MeterReading.objects.none()
    # Deleting a reading would silently change the usage billed from the one
    # after it; a wrong figure is corrected by editing it instead.
    http_method_names = ["get", "post", "patch", "head", "options"]

    def get_queryset(self):
        user = self.request.user
        qs = MeterReading.objects.select_related("unit", "charge", "recorded_by")
        if user.is_landlord:
            return qs.filter(unit__property__owner=user)
        if user.is_caretaker:
            return qs.filter(unit__property__caretaker=user)
        return MeterReading.objects.none()

    def perform_create(self, serializer):
        _validate_managed_property(self.request.user, serializer.validated_data["unit"].property)
        reading = serializer.save(recorded_by=self.request.user)
        _bill_late(reading)

    def perform_update(self, serializer):
        from apps.payments.billing import next_month
        from apps.payments.models import Invoice

        reading = serializer.instance
        _validate_managed_property(self.request.user, reading.unit.property)
        # Once usage has been billed, changing the reading would leave the bill
        # quoting figures the record no longer holds.
        if Invoice.objects.filter(
            tenancy__unit=reading.unit,
            period_start=next_month(reading.period),
            line_items__charge_type=reading.charge.charge_type,
            line_items__current_reading__isnull=False,
        ).exists():
            raise PermissionDenied(
                "This reading has already been billed. Adjust the tenant's bill instead."
            )
        serializer.save()

    @action(detail=False, methods=["get"])
    def sheet(self, request):
        """Every metered unit in a property for one month, with last month's
        reading filled in, so readings can be entered round the building.

        GET ?property=<id>&period=YYYY-MM-DD
        """
        from datetime import date

        try:
            property_ = Property.objects.get(pk=request.query_params.get("property"))
            period = date.fromisoformat(request.query_params.get("period", "")).replace(day=1)
        except (Property.DoesNotExist, ValueError, TypeError):
            return Response({"error": "property and period (YYYY-MM-DD) are required."}, status=400)
        _validate_managed_property(request.user, property_)

        charges = PropertyCharge.objects.filter(
            property=property_, is_active=True,
            billing_method=PropertyCharge.BillingMethod.METERED,
        )
        occupied = set(
            Tenancy.objects.filter(
                unit__property=property_, status=Tenancy.Status.ACTIVE
            ).values_list("unit_id", flat=True)
        )
        rows = []
        for unit in property_.units.order_by("unit_number"):
            for charge in charges:
                readings = MeterReading.objects.filter(unit=unit, charge=charge)
                current = readings.filter(period=period).first()
                previous = readings.filter(period__lt=period).order_by("-period").first()
                rows.append({
                    "unit": unit.id,
                    "unit_number": unit.unit_number,
                    "occupied": unit.id in occupied,
                    "charge": charge.id,
                    "charge_name": charge.name,
                    "unit_price": charge.unit_price,
                    "previous_reading": previous.reading if previous else None,
                    "reading_id": current.id if current else None,
                    "reading": current.reading if current else None,
                })
        return Response({"period": period, "rows": rows})


def _bill_late(reading):
    """Charge a reading entered after its bill went out, and tell the tenant."""
    from apps.notifications.tasks import send_sms
    from apps.payments.billing import bill_late_reading
    from apps.payments.services import how_to_pay

    for bill, line in bill_late_reading(reading):
        tenancy = bill.tenancy
        send_sms.delay(
            tenancy.tenant_id,
            f"Dear {tenancy.tenant.first_name}, your {bill.period_start:%B} bill has "
            f"been updated: {line['description']} KES {line['amount']:,.0f} added. "
            f"You now owe KES {bill.balance:,.0f}. {how_to_pay(tenancy.unit)}",
        )
