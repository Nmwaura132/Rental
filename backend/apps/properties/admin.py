from django.contrib import admin
from .models import Property, Unit


class UnitInline(admin.TabularInline):
    model = Unit
    extra = 0


@admin.register(Property)
class PropertyAdmin(admin.ModelAdmin):
    list_display = ["name", "owner", "county", "town", "created_at"]
    search_fields = ["name", "county", "town"]
    inlines = [UnitInline]


@admin.register(Unit)
class UnitAdmin(admin.ModelAdmin):
    list_display = ["unit_number", "property", "unit_type", "rent_amount", "status"]
    list_filter = ["status", "unit_type"]
