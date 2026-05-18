from rest_framework import serializers
from .models import Lease, MaintenanceRequest, MaintenanceNote


class LeaseSerializer(serializers.ModelSerializer):
    tenant_name = serializers.CharField(source="tenant.get_full_name", read_only=True)
    tenant_phone = serializers.CharField(source="tenant.phone_number", read_only=True)
    unit_number = serializers.CharField(source="unit.unit_number", read_only=True)
    property_name = serializers.CharField(source="unit.property.name", read_only=True)
    property_id = serializers.IntegerField(source="unit.property_id", read_only=True)

    class Meta:
        model = Lease
        fields = [
            "id", "tenant", "unit", "start_date", "end_date", "rent_amount",
            "deposit_amount", "deposit_paid", "status", "notes", "created_at",
            "tenant_name", "tenant_phone", "unit_number", "property_name", "property_id",
        ]
        read_only_fields = ["id", "created_at"]


class MaintenanceNoteSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source="author.get_full_name", read_only=True)
    is_tenant = serializers.SerializerMethodField()

    class Meta:
        model = MaintenanceNote
        fields = ["id", "body", "author_name", "is_tenant", "created_at"]
        read_only_fields = ["id", "author_name", "is_tenant", "created_at"]

    def get_is_tenant(self, obj):
        return hasattr(obj.author, "is_tenant") and obj.author.is_tenant


class MaintenanceRequestSerializer(serializers.ModelSerializer):
    notes_count = serializers.IntegerField(source="notes.count", read_only=True)
    # WHY: the mobile list tile destructures these for the landlord-side badges
    # (so the landlord knows whose unit a request belongs to without tapping in).
    # The model only has `lease` FK; we expose the joined names as read-only
    # fields so a single GET /maintenance/ call covers the list view's needs.
    tenant_name = serializers.CharField(source="lease.tenant.get_full_name", read_only=True)
    tenant_phone = serializers.CharField(source="lease.tenant.phone_number", read_only=True)
    unit_number = serializers.CharField(source="lease.unit.unit_number", read_only=True)
    property_name = serializers.CharField(source="lease.unit.property.name", read_only=True)
    property_id = serializers.IntegerField(source="lease.unit.property_id", read_only=True)

    class Meta:
        model = MaintenanceRequest
        fields = "__all__"
        read_only_fields = ["id", "created_at", "updated_at", "resolved_at"]
