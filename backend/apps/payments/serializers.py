from rest_framework import serializers
from django.db import transaction
from .models import Invoice, Payment, InvoiceLineItem


class PaymentSerializer(serializers.ModelSerializer):
    method_display = serializers.CharField(source="get_method_display", read_only=True)

    class Meta:
        model = Payment
        fields = [
            "id", "invoice", "method", "method_display", "status", "amount",
            # M-Pesa
            "mpesa_receipt_number", "mpesa_phone",
            # Bank transfer
            "bank_name", "bank_account", "bank_reference", "bank_branch",
            "paid_at", "created_at",
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
    FINANCIAL_FIELDS = {
        "tenancy",
        "amount_due",
        "due_date",
        "period_start",
        "period_end",
        "line_items",
    }
    # WHY: explicit DecimalField so drf-spectacular can derive a concrete schema type.
    # ReadOnlyField alone defaults to "string" because the source is a @property.
    balance = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    payments = PaymentSerializer(many=True, read_only=True)
    line_items = InvoiceLineItemSerializer(many=True, required=False)
    tenant_name = serializers.CharField(source="tenancy.tenant.get_full_name", read_only=True)
    unit_number = serializers.CharField(source="tenancy.unit.unit_number", read_only=True)

    class Meta:
        model = Invoice
        fields = [
            "id", "invoice_number", "tenancy", "tenant_name", "unit_number",
            "amount_due", "amount_paid", "balance", "due_date",
            "status", "period_start", "period_end", "notes",
            "payments", "line_items",
            "created_at",
        ]
        read_only_fields = ["id", "invoice_number", "amount_paid", "status", "created_at"]

    def validate(self, attrs):
        if (
            self.instance
            and self.instance.payments.exists()
            and self.FINANCIAL_FIELDS.intersection(self.initial_data)
        ):
            raise serializers.ValidationError(
                "Financial fields cannot be changed after a payment is recorded."
            )
        period_start = attrs.get(
            "period_start",
            self.instance.period_start if self.instance else None,
        )
        period_end = attrs.get(
            "period_end",
            self.instance.period_end if self.instance else None,
        )
        if period_start and period_end and period_end < period_start:
            raise serializers.ValidationError(
                {"period_end": "Period end must be on or after period start."}
            )
        return attrs

    @transaction.atomic
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

    @transaction.atomic
    def update(self, instance, validated_data):
        line_items_data = validated_data.pop("line_items", None)
        if line_items_data is not None:
            validated_data["amount_due"] = sum(
                item["amount"] for item in line_items_data
            )
        invoice = super().update(instance, validated_data)
        if line_items_data is not None:
            invoice.line_items.all().delete()
            InvoiceLineItem.objects.bulk_create(
                [
                    InvoiceLineItem(invoice=invoice, **item)
                    for item in line_items_data
                ]
            )
        return invoice
