from django.db import models
from django.conf import settings


class Notification(models.Model):
    class Channel(models.TextChoices):
        SMS = "sms", "SMS"
        WHATSAPP = "whatsapp", "WhatsApp"
        EMAIL = "email", "Email"
        PUSH = "push", "Push"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        SENT = "sent", "Sent"
        FAILED = "failed", "Failed"

    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="notifications", db_index=True,
    )
    channel = models.CharField(max_length=10, choices=Channel.choices)
    subject = models.CharField(max_length=120, blank=True)
    message = models.TextField()
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING, db_index=True)
    error = models.TextField(blank=True)
    sent_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "notifications"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["recipient", "status"]),
        ]

    def __str__(self):
        return f"{self.channel} to {self.recipient} ({self.status})"
