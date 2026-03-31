from rest_framework import serializers
from .models import Lease, MaintenanceRequest


class LeaseSerializer(serializers.ModelSerializer):
    tenant_name = serializers.CharField(source="tenant.get_full_name", read_only=True)
    tenant_phone = serializers.CharField(source="tenant.phone_number", read_only=True)
    unit_number = serializers.CharField(source="unit.unit_number", read_only=True)
    property_name = serializers.CharField(source="unit.property.name", read_only=True)
    property_id = serializers.IntegerField(source="unit.property_id", read_only=True)

    class Meta:
        model = Lease
        fields = "__all__"
        read_only_fields = ["id", "created_at"]


class MaintenanceRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = MaintenanceRequest
        fields = "__all__"
        read_only_fields = ["id", "created_at", "updated_at", "resolved_at"]
