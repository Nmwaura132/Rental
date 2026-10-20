from django.contrib import admin
from .models import Invoice, Payment, PaymentAccount


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    list_display = ["invoice_number", "tenancy", "amount_due", "amount_paid", "status", "due_date"]
    list_filter = ["status"]
    search_fields = ["invoice_number", "tenancy__tenant__phone_number"]


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ["mpesa_receipt_number", "invoice", "method", "amount", "status", "paid_at"]
    list_filter = ["method", "status"]
    search_fields = ["mpesa_receipt_number", "mpesa_phone"]


@admin.register(PaymentAccount)
class PaymentAccountAdmin(admin.ModelAdmin):
    """Where staff finish connecting a landlord's KCB paybill: paste the
    notification secret from KCB and set the status to Active."""

    list_display = ["owner", "kind", "number", "account_prefix", "status", "created_at"]
    list_filter = ["kind", "status"]
    search_fields = ["number", "account_number", "owner__phone_number"]
