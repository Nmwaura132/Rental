from django.db import models
from django.conf import settings
import random
import string

def _generate_unit_hash(length=4):
    """Generate a random alphanumeric suffix for global M-Pesa unit matching."""
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=length))


class Property(models.Model):
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="properties", db_index=True,
    )
    caretaker = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        related_name="managed_properties", null=True, blank=True,
    )
    name = models.CharField(max_length=120)
    address = models.TextField(blank=True, default="")
    county = models.CharField(max_length=60, blank=True, default="")
    town = models.CharField(max_length=60, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "properties"
        verbose_name_plural = "properties"
        ordering = ["name"]

    def __str__(self):
        return self.name


class Unit(models.Model):
    class UnitType(models.TextChoices):
        BEDSITTER = "bedsitter", "Bedsitter"
        ONE_BED = "1bed", "1 Bedroom"
        TWO_BED = "2bed", "2 Bedroom"
        THREE_BED = "3bed", "3 Bedroom"
        STUDIO = "studio", "Studio"
        COMMERCIAL = "commercial", "Commercial"

    class Status(models.TextChoices):
        VACANT = "vacant", "Vacant"
        OCCUPIED = "occupied", "Occupied"
        MAINTENANCE = "maintenance", "Under Maintenance"

    property = models.ForeignKey(Property, on_delete=models.CASCADE, related_name="units")
    unit_number = models.CharField(max_length=20)
    unit_type = models.CharField(max_length=20, choices=UnitType.choices)
    rent_amount = models.DecimalField(max_digits=10, decimal_places=2)
    deposit_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.VACANT, db_index=True)
    floor = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "units"
        unique_together = ("property", "unit_number")
        ordering = ["floor", "unit_number"]
        indexes = [
            models.Index(fields=["property", "status"]),
        ]

    def save(self, *args, **kwargs):
        # On creation, append a random suffix to ensure global uniqueness for M-Pesa matching
        if not self.pk and self.unit_number:
            suffix = _generate_unit_hash()
            # max_length is 20, we need 5 chars for "-XXXX"
            base_number = str(self.unit_number)[:14]
            self.unit_number = f"{base_number}-{suffix}"
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.property.name} — Unit {self.unit_number}"


class PropertyCharge(models.Model):
    class ChargeType(models.TextChoices):
        WATER = "water", "Water"
        ELECTRICITY = "electricity", "Electricity"
        GARBAGE = "garbage", "Garbage / Refuse"
        SERVICE = "service", "Service Charge"
        SECURITY = "security", "Security"
        SEWER = "sewer", "Sewerage"
        OTHER = "other", "Other"

    class BillingMethod(models.TextChoices):
        METERED = "metered", "Metered (per unit)"
        FLAT = "flat", "Flat Fee"

    property = models.ForeignKey(Property, on_delete=models.CASCADE, related_name="charges")
    charge_type = models.CharField(max_length=20, choices=ChargeType.choices)
    name = models.CharField(max_length=80)
    billing_method = models.CharField(
        max_length=10, choices=BillingMethod.choices, default=BillingMethod.FLAT
    )
    unit_price = models.DecimalField(max_digits=8, decimal_places=2)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "property_charges"
        unique_together = ("property", "charge_type")
        ordering = ["charge_type"]

    def __str__(self):
        return f"{self.property.name} — {self.name}"
