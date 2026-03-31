from django.contrib import admin
from .models import Invoice, Payment


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    list_display = ["invoice_number", "lease", "amount_due", "amount_paid", "status", "due_date"]
    list_filter = ["status"]
    search_fields = ["invoice_number", "lease__tenant__phone_number"]


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ["mpesa_receipt_number", "invoice", "method", "amount", "status", "paid_at"]
    list_filter = ["method", "status"]
    search_fields = ["mpesa_receipt_number", "mpesa_phone"]
