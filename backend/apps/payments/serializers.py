from rest_framework import serializers
from .models import Invoice, Payment, InvoiceLineItem


class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = [
            "id", "invoice", "method", "status", "amount",
            "mpesa_receipt_number", "mpesa_phone", "paid_at", "created_at",
        ]
        read_only_fields = fields


class InvoiceLineItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = InvoiceLineItem
        fields = [
            "id", "description", "charge_type",
            "previous_reading", "current_reading", "units_consumed",
            "unit_price", "amount",
        ]
        read_only_fields = ["id"]


class InvoiceSerializer(serializers.ModelSerializer):
    balance = serializers.ReadOnlyField()
    payments = PaymentSerializer(many=True, read_only=True)
    line_items = InvoiceLineItemSerializer(many=True, required=False)
    tenant_name = serializers.CharField(source="lease.tenant.get_full_name", read_only=True)
    unit_number = serializers.CharField(source="lease.unit.unit_number", read_only=True)

    class Meta:
        model = Invoice
        fields = [
            "id", "invoice_number", "lease", "tenant_name", "unit_number",
            "amount_due", "amount_paid", "balance", "due_date",
            "status", "period_start", "period_end", "notes",
            "payments", "line_items",
            "created_at",
        ]
        read_only_fields = ["id", "invoice_number", "amount_paid", "status", "created_at"]

    def create(self, validated_data):
        import uuid
        line_items_data = validated_data.pop("line_items", [])
        period_start = validated_data.get("period_start")
        prefix = period_start.strftime("%Y%m") if period_start else "MAN"
        validated_data["invoice_number"] = f"INV-{prefix}-{uuid.uuid4().hex[:6].upper()}"
        # If line items provided, compute amount_due from their sum
        if line_items_data:
            validated_data["amount_due"] = sum(item["amount"] for item in line_items_data)
        invoice = Invoice.objects.create(**validated_data)
        for item in line_items_data:
            InvoiceLineItem.objects.create(invoice=invoice, **item)
        return invoice
