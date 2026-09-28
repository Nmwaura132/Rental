from rest_framework import serializers
from .models import MeterReading, Property, PropertyCharge, Unit


class UnitSerializer(serializers.ModelSerializer):
    class Meta:
        model = Unit
        fields = "__all__"
        # WHY payment_code is read-only: it's derived from unit_number in
        # Unit.save() with its own collision handling. Letting it through the
        # API would let a client set a duplicate or bypass that logic entirely.
        read_only_fields = ["id", "created_at", "payment_code"]


class PropertyChargeSerializer(serializers.ModelSerializer):
    class Meta:
        model = PropertyCharge
        fields = ["id", "property", "charge_type", "name", "billing_method", "unit_price", "is_active"]
        read_only_fields = ["id"]


class PropertySerializer(serializers.ModelSerializer):
    units = UnitSerializer(many=True, read_only=True)
    charges = PropertyChargeSerializer(many=True, read_only=True)
    unit_count = serializers.SerializerMethodField()
    vacant_count = serializers.SerializerMethodField()

    class Meta:
        model = Property
        fields = [
            "id", "name", "address", "county", "town", "lr_number",
            "caretaker", "unit_count", "vacant_count", "units", "charges", "created_at",
        ]
        read_only_fields = ["id", "owner", "created_at"]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # WHY owner-only: lr_number is the title's Land Reference, collected for
        # the landlord's own KRA filing. Tenants and caretakers can read this
        # serializer for the property they occupy or manage, and the LR number
        # is enough to look up the landlord's title in the land registry.
        request = self.context.get("request")
        viewer = getattr(request, "user", None)
        if viewer is None or viewer.id != instance.owner_id:
            data.pop("lr_number", None)
        return data

    def get_unit_count(self, obj) -> int:
        return len(obj.units.all())

    def get_vacant_count(self, obj) -> int:
        return len([u for u in obj.units.all() if u.status == "vacant"])

    def validate_caretaker(self, value):
        if value is not None and not value.is_caretaker:
            raise serializers.ValidationError("The selected user is not a caretaker.")
        return value

    def create(self, validated_data):
        validated_data["owner"] = self.context["request"].user
        return super().create(validated_data)


class MeterReadingSerializer(serializers.ModelSerializer):
    previous_reading = serializers.SerializerMethodField()
    recorded_by_name = serializers.CharField(source="recorded_by.get_full_name", read_only=True)

    class Meta:
        model = MeterReading
        fields = [
            "id", "unit", "charge", "period", "reading",
            "previous_reading", "recorded_by_name", "recorded_at",
        ]
        read_only_fields = ["id", "recorded_by_name", "recorded_at"]

    def get_previous_reading(self, obj):
        previous = obj.previous()
        return previous.reading if previous else None

    def validate_period(self, value):
        # Any day in the month names that month's reading.
        return value.replace(day=1)

    def validate(self, attrs):
        unit = attrs.get("unit", getattr(self.instance, "unit", None))
        charge = attrs.get("charge", getattr(self.instance, "charge", None))
        period = attrs.get("period", getattr(self.instance, "period", None))
        reading = attrs.get("reading", getattr(self.instance, "reading", None))

        if charge.property_id != unit.property_id:
            raise serializers.ValidationError("That charge belongs to a different property.")
        if charge.billing_method != PropertyCharge.BillingMethod.METERED:
            raise serializers.ValidationError(f"{charge.name} is a flat charge and has no meter.")

        # A meter only counts up. A lower figure is almost always a slip, and
        # billing it would produce negative usage — a credit nobody intended.
        earlier = (
            MeterReading.objects.filter(unit=unit, charge=charge, period__lt=period)
            .exclude(pk=getattr(self.instance, "pk", None))
            .order_by("-period").first()
        )
        if earlier and reading < earlier.reading:
            raise serializers.ValidationError(
                f"{reading} is lower than the {earlier.period:%B} reading of "
                f"{earlier.reading}. Check the figure on the meter."
            )
        later = (
            MeterReading.objects.filter(unit=unit, charge=charge, period__gt=period)
            .exclude(pk=getattr(self.instance, "pk", None))
            .order_by("period").first()
        )
        if later and reading > later.reading:
            raise serializers.ValidationError(
                f"{reading} is higher than the {later.period:%B} reading of {later.reading}."
            )
        return attrs
