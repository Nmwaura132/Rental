from django.db import models
from apps.tenants.models import Lease


class Invoice(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PAID = "paid", "Paid"
        PARTIALLY_PAID = "partially_paid", "Partially Paid"
        OVERDUE = "overdue", "Overdue"
        CANCELLED = "cancelled", "Cancelled"

    lease = models.ForeignKey(Lease, on_delete=models.PROTECT, related_name="invoices", db_index=True)
    invoice_number = models.CharField(max_length=20, unique=True, db_index=True)
    amount_due = models.DecimalField(max_digits=10, decimal_places=2)
    amount_paid = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    due_date = models.DateField(db_index=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True)
    period_start = models.DateField()
    period_end = models.DateField()
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "invoices"
        ordering = ["-due_date"]
        indexes = [
            models.Index(fields=["status", "due_date"]),
            models.Index(fields=["lease", "status"]),
        ]

    def __str__(self):
        return f"Invoice {self.invoice_number} — {self.status}"

    @property
    def balance(self):
        return self.amount_due - self.amount_paid


class Payment(models.Model):
    class Method(models.TextChoices):
        MPESA = "mpesa", "M-Pesa"
        AIRTEL = "airtel", "Airtel Money"
        BANK = "bank", "Bank Transfer"
        CASH = "cash", "Cash"
        CARD = "card", "Card"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        CONFIRMED = "confirmed", "Confirmed"
        FAILED = "failed", "Failed"
        REVERSED = "reversed", "Reversed"

    invoice = models.ForeignKey(Invoice, on_delete=models.PROTECT, related_name="payments", db_index=True)
    method = models.CharField(max_length=10, choices=Method.choices, db_index=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING, db_index=True)
    amount = models.DecimalField(max_digits=10, decimal_places=2)

    # M-Pesa specific fields
    mpesa_receipt_number = models.CharField(max_length=20, blank=True, null=True, unique=True)
    mpesa_transaction_id = models.CharField(max_length=40, blank=True, null=True)
    mpesa_phone = models.CharField(max_length=15, blank=True, null=True)
    mpesa_account_ref = models.CharField(max_length=20, blank=True, null=True)  # unit number tenant used

    # Idempotency — prevents double-recording webhook retries
    idempotency_key = models.CharField(max_length=60, unique=True, db_index=True)

    paid_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "payments"
        indexes = [
            models.Index(fields=["method", "status"]),
            models.Index(fields=["mpesa_receipt_number"]),
        ]

    def __str__(self):
        return f"{self.method} — KES {self.amount} ({self.status})"


class MpesaSTKRequest(models.Model):
    """Tracks every STK Push initiation and its callback outcome."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        SUCCESS = "success", "Success"
        FAILED = "failed", "Failed"
        CANCELLED = "cancelled", "Cancelled by User"

    # Populated on initiation
    checkout_request_id = models.CharField(max_length=100, unique=True, db_index=True)
    merchant_request_id = models.CharField(max_length=100, db_index=True)
    phone = models.CharField(max_length=15)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    account_ref = models.CharField(max_length=12)
    invoice = models.ForeignKey(
        Invoice, on_delete=models.SET_NULL, null=True, blank=True, related_name="stk_requests"
    )
    status = models.CharField(max_length=15, choices=Status.choices, default=Status.PENDING, db_index=True)

    # Populated from callback
    result_code = models.IntegerField(null=True, blank=True)
    result_desc = models.TextField(blank=True)
    mpesa_receipt_number = models.CharField(max_length=20, blank=True, null=True, unique=True)
    raw_callback = models.JSONField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "mpesa_stk_requests"
        ordering = ["-created_at"]

    def __str__(self):
        return f"STK {self.checkout_request_id[:20]} — {self.status}"


class InvoiceLineItem(models.Model):
    invoice = models.ForeignKey(Invoice, on_delete=models.CASCADE, related_name="line_items")
    description = models.CharField(max_length=120)
    charge_type = models.CharField(max_length=20)  # 'rent', 'water', 'electricity', etc.
    # Metered fields — null for flat charges
    previous_reading = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    current_reading = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    units_consumed = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    unit_price = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    amount = models.DecimalField(max_digits=10, decimal_places=2)

    class Meta:
        db_table = "invoice_line_items"
        ordering = ["id"]

    def __str__(self):
        return f"{self.description} — KES {self.amount}"
