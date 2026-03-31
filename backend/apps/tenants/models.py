from django.db import models
from django.conf import settings
from apps.properties.models import Unit


class Lease(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        EXPIRED = "expired", "Expired"
        TERMINATED = "terminated", "Terminated"

    tenant = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="leases", db_index=True,
    )
    unit = models.ForeignKey(Unit, on_delete=models.PROTECT, related_name="leases")
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    rent_amount = models.DecimalField(max_digits=10, decimal_places=2)  # locked at signing
    deposit_amount = models.DecimalField(max_digits=10, decimal_places=2)
    deposit_paid = models.BooleanField(default=False)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.ACTIVE, db_index=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "leases"
        indexes = [
            models.Index(fields=["status", "end_date"]),
            models.Index(fields=["tenant", "status"]),
        ]

    def __str__(self):
        return f"{self.tenant} — {self.unit} ({self.status})"


class MaintenanceRequest(models.Model):
    class Priority(models.TextChoices):
        LOW = "low", "Low"
        MEDIUM = "medium", "Medium"
        HIGH = "high", "High"
        URGENT = "urgent", "Urgent"

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        IN_PROGRESS = "in_progress", "In Progress"
        RESOLVED = "resolved", "Resolved"
        CLOSED = "closed", "Closed"

    lease = models.ForeignKey(Lease, on_delete=models.CASCADE, related_name="maintenance_requests")
    title = models.CharField(max_length=120)
    description = models.TextField()
    priority = models.CharField(max_length=10, choices=Priority.choices, default=Priority.MEDIUM)
    status = models.CharField(max_length=15, choices=Status.choices, default=Status.OPEN, db_index=True)
    photo = models.ImageField(upload_to="maintenance/%Y/%m/", null=True, blank=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "maintenance_requests"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.title} ({self.status})"
