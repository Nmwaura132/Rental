import re

from django.db import models
from django.conf import settings
import random
import string

# WHY exclude 0/O/1/I: these are the disambiguating suffix characters a tenant
# reads off an SMS/invoice and dials into their phone keypad; ambiguous glyphs
# there turn into wrong-account payments, not just typos.
_PAYMENT_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _slugify_unit_number(unit_number):
    """Uppercase, alphanumeric-only projection of a landlord's own unit label."""
    return re.sub(r"[^A-Z0-9]", "", unit_number.upper())


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
    # WHY unique only per-property, not globally: this is the landlord's own
    # label ("G1", "1A") — the whole point is that two different landlords
    # (or even two properties for the same landlord) can each have a "G1"
    # without colliding. Global uniqueness lives on payment_code instead.
    unit_number = models.CharField(max_length=20)
    # WHY a separate field: unit_number needs to be readable and landlord-chosen;
    # what a tenant dials into M-Pesa needs to be short, globally unique, and
    # free of characters that get misread on a phone keypad. Forcing one field
    # to do both meant every unit_number got a random suffix bolted on
    # ("G1-K3P9"), which broke the very thing landlords use it for.
    payment_code = models.CharField(max_length=12, unique=True, db_index=True)
    unit_type = models.CharField(max_length=20, choices=UnitType.choices)
    rent_amount = models.DecimalField(max_digits=10, decimal_places=2)
    deposit_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.VACANT, db_index=True)
    floor = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "units"
        ordering = ["floor", "unit_number"]
        constraints = [
            models.CheckConstraint(condition=models.Q(rent_amount__gt=0), name="unit_rent_positive"),
            models.CheckConstraint(condition=models.Q(deposit_amount__gte=0), name="unit_deposit_nonnegative"),
            models.UniqueConstraint(fields=["property", "unit_number"], name="unit_number_unique_per_property"),
        ]
        indexes = [
            models.Index(fields=["property", "status"]),
        ]

    def _next_payment_code(self):
        """
        Derive a payment code from unit_number, falling back to a random
        suffix only on an actual collision.

        WHY derive-with-fallback rather than always-random: most units never
        collide across the whole system ("G1" is globally unique in practice
        even though it's only guaranteed unique per-property), so most
        landlords see their own label on the invoice unchanged. A random code
        for every unit would make ALL of them equally unmemorable to solve a
        collision that, for most units, never happens.
        """
        base = _slugify_unit_number(self.unit_number)[:12] or "UNIT"
        if not Unit.objects.filter(payment_code__iexact=base).exists():
            return base
        for _ in range(20):
            suffix = "".join(random.choices(_PAYMENT_CODE_ALPHABET, k=4))
            candidate = f"{base[:7]}{suffix}"[:12]
            if not Unit.objects.filter(payment_code__iexact=candidate).exists():
                return candidate
        # Astronomically unlikely with a 32-char alphabet and 4-char suffix,
        # but fail loudly rather than save a colliding payment_code.
        raise RuntimeError(f"Could not derive a unique payment_code from '{self.unit_number}'.")

    def save(self, *args, **kwargs):
        if not self.pk and not self.payment_code:
            self.payment_code = self._next_payment_code()
        super().save(*args, **kwargs)

    @classmethod
    def match_reference(cls, reference):
        """
        Resolve whatever a tenant typed into a Paybill/bank reference field to
        a single Unit, or None.

        Tries payment_code first — the intended path, since it's what's
        printed on invoices and SMS and is globally unique by construction.
        Falls back to unit_number (normalized: uppercased, punctuation/space
        stripped) for tenants who type what their landlord actually calls the
        unit instead ("G1") rather than the system code. Because unit_number
        is only unique per-property, this fallback can match more than one
        unit across different landlords — returns None rather than guessing
        wrong when that happens, since crediting the wrong landlord's tenant
        is worse than not auto-matching at all.
        """
        reference = (reference or "").strip()
        if not reference:
            return None

        unit = cls.objects.filter(payment_code__iexact=reference).first()
        if unit:
            return unit

        # Second indexed lookup, not a table scan: strip the space/dash
        # punctuation a tenant might type ("1-A", "G 1") from the *input*
        # only, then match it as-is against stored unit_number. Landlords who
        # store unit_number with unusual internal punctuation of their own
        # ("1.A") won't hit this path — falls through to manual reconciliation,
        # same as any other unrecognised reference today.
        slug = _slugify_unit_number(reference)
        if not slug:
            return None
        candidates = list(cls.objects.filter(unit_number__iexact=slug)[:2])
        return candidates[0] if len(candidates) == 1 else None

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
        constraints = [
            models.CheckConstraint(condition=models.Q(unit_price__gte=0), name="property_charge_price_nonnegative"),
        ]

    def __str__(self):
        return f"{self.property.name} — {self.name}"
