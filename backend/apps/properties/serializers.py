from rest_framework import serializers
from .models import Property, Unit, PropertyCharge


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
            "id", "name", "address", "county", "town",
            "caretaker", "unit_count", "vacant_count", "units", "charges", "created_at",
        ]
        read_only_fields = ["id", "owner", "created_at"]

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
