from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone
from apps.core.utils.phone import validate_phone, normalize_phone


class UserManager(BaseUserManager):
    def create_user(self, phone_number, password=None, **extra_fields):
        if not phone_number:
            raise ValueError("Phone number is required")
        
        # Normalize on creation
        phone_number = normalize_phone(phone_number)
        
        extra_fields.setdefault("is_active", True)
        user = self.model(phone_number=phone_number, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone_number, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("role", User.Role.LANDLORD)
        return self.create_user(phone_number, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    class Role(models.TextChoices):
        LANDLORD = "landlord", "Landlord"
        TENANT = "tenant", "Tenant"
        CARETAKER = "caretaker", "Caretaker"

    # Primary identifier is phone number (critical for M-Pesa matching)
    phone_number = models.CharField(
        max_length=15, 
        unique=True, 
        db_index=True,
        validators=[validate_phone],
        help_text="E.164 format (e.g. +254712345678)"
    )
    email = models.EmailField(blank=True, null=True, unique=True)
    first_name = models.CharField(max_length=60)
    last_name = models.CharField(max_length=60)
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.TENANT, db_index=True)

    # Kenya-specific identity fields
    national_id = models.CharField(max_length=20, blank=True, null=True, unique=True)
    kra_pin = models.CharField(max_length=11, blank=True, null=True)  # e.g. A000000000A

    # Tenant profile fields
    occupation = models.CharField(max_length=100, blank=True, null=True)
    next_of_kin_name = models.CharField(max_length=120, blank=True, null=True)
    next_of_kin_phone = models.CharField(
        max_length=15,
        blank=True,
        null=True,
        validators=[validate_phone]
    )

    # ID document photos (stored in MinIO)
    id_front_photo = models.URLField(max_length=500, blank=True, null=True)
    id_back_photo = models.URLField(max_length=500, blank=True, null=True)

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    is_verified = models.BooleanField(default=False)  # phone/email verified

    date_joined = models.DateTimeField(default=timezone.now)
    last_login = models.DateTimeField(null=True, blank=True)

    objects = UserManager()

    USERNAME_FIELD = "phone_number"
    REQUIRED_FIELDS = ["first_name", "last_name"]

    class Meta:
        db_table = "users"
        indexes = [
            models.Index(fields=["role", "is_active"]),
        ]

    def save(self, *args, **kwargs):
        # Always normalize before saving to the DB
        if self.phone_number:
            self.phone_number = normalize_phone(self.phone_number)
        if self.next_of_kin_phone:
            self.next_of_kin_phone = normalize_phone(self.next_of_kin_phone)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.get_full_name()} ({self.phone_number})"

    def get_full_name(self):
        return f"{self.first_name} {self.last_name}".strip()

    @property
    def is_landlord(self):
        return self.role == self.Role.LANDLORD

    @property
    def is_tenant(self):
        return self.role == self.Role.TENANT

    @property
    def is_caretaker(self):
        return self.role == self.Role.CARETAKER
