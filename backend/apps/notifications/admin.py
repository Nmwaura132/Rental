from django.contrib import admin
from .models import Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ["recipient", "channel", "status", "sent_at", "created_at"]
    list_filter = ["channel", "status"]
    search_fields = ["recipient__phone_number", "message"]
