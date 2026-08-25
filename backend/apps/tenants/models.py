from django.db import models
from django.conf import settings
from apps.properties.models import Unit


class Tenancy(models.Model):
    """A tenant's occupancy of a unit at an agreed rent.

    WHY "tenancy" and not "lease": Kenyan residential renting rarely involves a
    signed lease, and KRA's own eRITS wording is "tenancy agreement". The record
    is the same either way — it is what links a tenant to a unit, fixes the rent
    invoices are raised against, and supplies the rent roll KRA expects.
    """

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        EXPIRED = "expired", "Expired"
        TERMINATED = "terminated", "Terminated"

    tenant = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="tenancies", db_index=True,
    )
    unit = models.ForeignKey(Unit, on_delete=models.PROTECT, related_name="tenancies")
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    rent_amount = models.DecimalField(max_digits=10, decimal_places=2)  # locked at agreement
    deposit_amount = models.DecimalField(max_digits=10, decimal_places=2)
    deposit_paid = models.BooleanField(default=False)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.ACTIVE, db_index=True)
    notes = models.TextField(blank=True)
    document_key = models.CharField(max_length=500, blank=True)

    # ── Notice to vacate ─────────────────────────────────────────────────────
    # An open-ended tenancy ends by notice rather than by reaching a date, so
    # this is how most Kenyan tenancies actually terminate.
    notice_given_at = models.DateTimeField(null=True, blank=True)
    notice_effective_date = models.DateField(
        null=True, blank=True,
        help_text="The day the tenant intends to vacate.",
    )
    notice_reason = models.TextField(
        blank=True,
        help_text="The tenant's own words, kept as the written record.",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "tenancies"
        # WHY explicit ordering: this queryset is paginated, and paginating an
        # unordered queryset lets rows shift between pages — the same tenancy
        # showing twice, or none at all, as a landlord pages through.
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(condition=models.Q(rent_amount__gt=0), name="tenancy_rent_positive"),
            models.CheckConstraint(condition=models.Q(deposit_amount__gte=0), name="tenancy_deposit_nonnegative"),
            models.CheckConstraint(
                condition=models.Q(end_date__isnull=True) | models.Q(end_date__gte=models.F("start_date")),
                name="tenancy_dates_valid",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "end_date"]),
            models.Index(fields=["tenant", "status"]),
        ]

    def __str__(self):
        return f"{self.tenant} — {self.unit} ({self.status})"

    @property
    def has_notice(self) -> bool:
        return self.notice_given_at is not None


from apps.core.storage_backends import private_media_storage

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
    tenancy = models.ForeignKey(Tenancy, on_delete=models.CASCADE, related_name="maintenance_requests")
    title = models.CharField(max_length=120)
    description = models.TextField()
    priority = models.CharField(max_length=10, choices=Priority.choices, default=Priority.MEDIUM)
    status = models.CharField(max_length=15, choices=Status.choices, default=Status.OPEN, db_index=True)
    photo = models.ImageField(
        upload_to="maintenance/%Y/%m/",
        null=True,
        blank=True,
        storage=private_media_storage,
    )
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "maintenance_requests"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.title} ({self.status})"


class MaintenanceNote(models.Model):
    request = models.ForeignKey(
        MaintenanceRequest, on_delete=models.CASCADE, related_name="notes"
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="maintenance_notes"
    )
    body = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "maintenance_notes"
        ordering = ["created_at"]

    def __str__(self):
        return f"Note by {self.author} on {self.request_id}"
