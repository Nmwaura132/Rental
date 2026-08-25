from rest_framework import serializers
from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    # The app keys its unread styling off this name.
    is_read = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = [
            "id", "channel", "subject", "message", "status",
            "sent_at", "read_at", "is_read", "created_at",
        ]
        read_only_fields = fields

    def get_is_read(self, obj) -> bool:
        return obj.read_at is not None
