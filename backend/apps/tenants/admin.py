from django.contrib import admin
from .models import Tenancy, MaintenanceRequest


@admin.register(Tenancy)
class TenancyAdmin(admin.ModelAdmin):
    list_display = ["tenant", "unit", "rent_amount", "status", "start_date", "end_date"]
    list_filter = ["status"]
    search_fields = ["tenant__phone_number", "tenant__first_name", "unit__unit_number"]


@admin.register(MaintenanceRequest)
class MaintenanceRequestAdmin(admin.ModelAdmin):
    list_display = ["title", "tenancy", "priority", "status", "created_at"]
    list_filter = ["status", "priority"]
