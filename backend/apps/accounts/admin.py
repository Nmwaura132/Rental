from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = ["phone_number", "first_name", "last_name", "role", "is_active", "is_verified", "date_joined"]
    list_filter = ["role", "is_active", "is_verified", "is_staff"]
    search_fields = ["phone_number", "first_name", "last_name", "email", "national_id"]
    ordering = ["-date_joined"]

    fieldsets = (
        (None, {"fields": ("phone_number", "password")}),
        ("Personal info", {"fields": ("first_name", "last_name", "email", "national_id", "kra_pin")}),
        ("Role & Status", {"fields": ("role", "is_active", "is_verified", "is_staff", "is_superuser")}),
        ("Permissions", {"fields": ("groups", "user_permissions")}),
    )
    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("phone_number", "first_name", "last_name", "role", "password1", "password2"),
        }),
    )
