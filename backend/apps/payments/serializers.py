from rest_framework import serializers
from django.db import transaction
from .models import PaymentAccount, Invoice, Payment, InvoiceLineItem
from .services import pay_to


class PaymentSerializer(serializers.ModelSerializer):
    method_display = serializers.CharField(source="get_method_display", read_only=True)
    # Who paid and for what, so a list of payments reads without opening each
    # bill.
    tenant_name = serializers.CharField(source="invoice.tenancy.tenant.get_full_name", read_only=True)
    unit_number = serializers.CharField(source="invoice.tenancy.unit.unit_number", read_only=True)
    property_name = serializers.CharField(source="invoice.tenancy.unit.property.name", read_only=True)
    invoice_number = serializers.CharField(source="invoice.invoice_number", read_only=True)
    period_start = serializers.DateField(source="invoice.period_start", read_only=True)

    class Meta:
        model = Payment
        fields = [
            "id", "invoice", "invoice_number", "period_start",
            "tenant_name", "unit_number", "property_name",
            "method", "method_display", "status", "amount",
            # M-Pesa
            "mpesa_receipt_number", "mpesa_phone",
            # Bank transfer
            "bank_name", "bank_account", "bank_reference", "bank_branch",
            "etims_receipt_number",
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
    # The app's "how to pay" panel read mpesa_paybill from the invoice, which
    # was never sent — so every tenant saw "Ask your landlord" — and showed the
    # unit number where the payment code belongs.
    mpesa_paybill = serializers.SerializerMethodField()
    pay_account = serializers.SerializerMethodField()

    class Meta:
        model = Invoice
        fields = [
            "id", "invoice_number", "tenancy", "tenant_name", "unit_number",
            "amount_due", "amount_paid", "balance", "due_date",
            "status", "period_start", "period_end", "notes",
            "payments", "line_items",
            "mpesa_paybill", "pay_account",
            "created_at",
        ]
        read_only_fields = ["id", "invoice_number", "amount_paid", "status", "created_at"]

    def get_mpesa_paybill(self, invoice):
        return pay_to(invoice.tenancy.unit)[0]

    def get_pay_account(self, invoice):
        return pay_to(invoice.tenancy.unit)[1]

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


class PaymentAccountSerializer(serializers.ModelSerializer):
    """A landlord's own way of being paid. The KCB secret is never exposed and
    the status is set by the server: a KCB paybill is "connecting" until staff
    finish the link."""

    kind_display = serializers.CharField(source="get_kind_display", read_only=True)

    class Meta:
        model = PaymentAccount
        fields = [
            "id", "kind", "kind_display", "status", "number", "account_prefix",
            "bank_name", "bank_branch", "account_name", "account_number", "created_at",
        ]
        read_only_fields = ["status", "created_at"]

    def validate(self, attrs):
        import re

        kind = attrs.get("kind", getattr(self.instance, "kind", None))
        if self.instance is not None and kind != self.instance.kind:
            raise serializers.ValidationError({"kind": "Add a new method rather than changing this one's type."})

        def value(name):
            return (attrs.get(name, getattr(self.instance, name, "")) or "").strip()

        K = PaymentAccount.Kind
        errors = {}
        if kind in (K.KCB_PAYBILL, K.PAYBILL, K.TILL):
            if not re.fullmatch(r"\d{5,8}", value("number")):
                errors["number"] = "Enter the 5 to 8 digit number."
            if kind == K.TILL and value("account_prefix"):
                errors["account_prefix"] = "A till has no account number."
        if kind == K.BANK:
            for name, label in (("bank_name", "bank"), ("account_name", "account name"),
                                ("account_number", "account number")):
                if not value(name):
                    errors[name] = f"Enter the {label}."
        if kind == K.CASH:
            owner = self.context["request"].user
            others = PaymentAccount.objects.filter(owner=owner, kind=K.CASH)
            if self.instance is not None:
                others = others.exclude(pk=self.instance.pk)
            if others.exists():
                errors["kind"] = "Cash is already set up."
        if kind == K.KCB_PAYBILL:
            taken = PaymentAccount.objects.filter(kind=K.KCB_PAYBILL, number=value("number"))
            if self.instance is not None:
                taken = taken.exclude(pk=self.instance.pk)
            if taken.exists():
                errors["number"] = "This KCB paybill is already connected to another account. Contact support."
        if errors:
            raise serializers.ValidationError(errors)
        return attrs
