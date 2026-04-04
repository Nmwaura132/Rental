import logging
import uuid
from decimal import Decimal
from django.utils import timezone
from django.db.models import Sum, Count, Q
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Invoice, Payment, MpesaSTKRequest
from .serializers import InvoiceSerializer, PaymentSerializer
from .mpesa import make_idempotency_key

logger = logging.getLogger(__name__)


def _invoice_qs_for_user(user):
    if user.is_landlord:
        return Invoice.objects.filter(lease__unit__property__owner=user)
    if user.is_caretaker:
        return Invoice.objects.filter(lease__unit__property__caretaker=user)
    return Invoice.objects.filter(lease__tenant=user)


def _payment_qs_for_user(user):
    if user.is_landlord:
        return Payment.objects.filter(invoice__lease__unit__property__owner=user)
    if user.is_caretaker:
        return Payment.objects.filter(invoice__lease__unit__property__caretaker=user)
    return Payment.objects.filter(invoice__lease__tenant=user)


class InvoiceViewSet(viewsets.ModelViewSet):
    serializer_class = InvoiceSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["status", "lease"]

    def get_queryset(self):
        return _invoice_qs_for_user(self.request.user).select_related(
            "lease__tenant", "lease__unit"
        ).prefetch_related("line_items", "payments")

    def perform_create(self, serializer):
        super().perform_create(serializer)
        invoice = Invoice.objects.select_related(
            "lease__tenant", "lease__unit__property"
        ).get(pk=serializer.instance.pk)
        from apps.notifications.tasks import send_sms
        from django.conf import settings
        tenant = invoice.lease.tenant
        unit = invoice.lease.unit
        msg = (
            f"Dear {tenant.first_name}, invoice {invoice.invoice_number} "
            f"for {unit.property.name} Unit {unit.unit_number} "
            f"has been issued. Amount: KES {invoice.amount_due:,.0f}. "
            f"Due: {invoice.due_date.strftime('%d %b %Y')}. "
            f"Pay via M-Pesa Paybill {settings.MPESA_SHORTCODE}, "
            f"Acc: {unit.unit_number}."
        )
        send_sms.delay(tenant.id, msg)

    def perform_destroy(self, instance):
        # Payment.invoice uses PROTECT — delete payments first
        instance.payments.all().delete()
        instance.delete()


class PaymentViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = PaymentSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["method", "status"]

    def get_queryset(self):
        return _payment_qs_for_user(self.request.user).select_related(
            "invoice__lease__tenant"
        )

    @action(detail=False, methods=["post"], url_path="record",
            permission_classes=[permissions.IsAuthenticated])
    def record_payment(self, request):
        """
        Manually record a cash or bank payment — landlords/caretakers only.
        Tenants pay via STK Push. Body: { invoice, method, amount }
        """
        if request.user.is_tenant:
            return Response(
                {"error": "Tenants cannot record manual payments. Use M-Pesa STK Push to pay."},
                status=status.HTTP_403_FORBIDDEN,
            )

        invoice_id = request.data.get("invoice")
        method = request.data.get("method")
        amount = request.data.get("amount")

        allowed_methods = [Payment.Method.CASH, Payment.Method.BANK]
        if method not in [m.value for m in allowed_methods]:
            return Response(
                {"error": f"Method must be one of: {[m.value for m in allowed_methods]}"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            amount = float(amount)
            if amount <= 0:
                raise ValueError
        except (TypeError, ValueError):
            return Response({"error": "Amount must be a positive number."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            invoice = _invoice_qs_for_user(request.user).get(id=invoice_id)
        except Invoice.DoesNotExist:
            return Response({"error": "Invoice not found."}, status=status.HTTP_404_NOT_FOUND)

        if invoice.status == Invoice.Status.PAID:
            return Response({"error": "Invoice is already fully paid."}, status=status.HTTP_400_BAD_REQUEST)

        payment = Payment.objects.create(
            invoice=invoice,
            method=method,
            status=Payment.Status.CONFIRMED,
            amount=amount,
            idempotency_key=f"{method}:{uuid.uuid4().hex}",
            paid_at=timezone.now(),
        )

        invoice.amount_paid = (invoice.amount_paid or Decimal('0')) + Decimal(str(payment.amount))
        invoice.status = (
            Invoice.Status.PAID if invoice.amount_paid >= invoice.amount_due
            else Invoice.Status.PARTIALLY_PAID
        )
        invoice.save(update_fields=["amount_paid", "status"])

        return Response(PaymentSerializer(payment).data, status=status.HTTP_201_CREATED)


class DashboardStatsView(APIView):
    """Summary stats for the landlord / caretaker dashboard. Cached 60s per user."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        from django.core.cache import cache
        cache_key = f"dashboard:{request.user.id}"
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)
        result = self._compute(request)
        cache.set(cache_key, result.data, timeout=60)
        return result

    def _compute(self, request):
        from apps.properties.models import Property, Unit
        from apps.tenants.models import Lease
        user = request.user

        if user.is_tenant:
            from django.conf import settings as django_settings
            # Tenant dashboard: balance, next due date, active lease/unit info
            invoices = Invoice.objects.filter(lease__tenant=user)
            _bal = invoices.filter(
                status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE, Invoice.Status.PARTIALLY_PAID]
            ).aggregate(due=Sum("amount_due"), paid=Sum("amount_paid"))
            total_balance = (_bal["due"] or 0) - (_bal["paid"] or 0)
            next_invoice = invoices.filter(
                status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE]
            ).order_by("due_date").first()
            lease = Lease.objects.filter(
                tenant=user, status=Lease.Status.ACTIVE
            ).select_related("unit__property").first()
            return Response({
                "outstanding_balance": total_balance,
                "next_due_date": next_invoice.due_date if next_invoice else None,
                "next_due_amount": next_invoice.balance if next_invoice else None,
                "unit_number": lease.unit.unit_number if lease else None,
                "property_name": lease.unit.property.name if lease else None,
                "monthly_rent": float(lease.rent_amount) if lease else None,
                "lease_start": lease.start_date.isoformat() if (lease and lease.start_date) else None,
                "lease_end": lease.end_date.isoformat() if (lease and lease.end_date) else None,
                "mpesa_paybill": getattr(django_settings, "MPESA_SHORTCODE", None),
            })

        # Landlord / caretaker dashboard
        if user.is_landlord:
            props = Property.objects.filter(owner=user)
        else:
            props = Property.objects.filter(caretaker=user)

        prop_ids = props.values_list("id", flat=True)
        units = Unit.objects.filter(property_id__in=prop_ids)
        leases = Lease.objects.filter(unit__property_id__in=prop_ids, status=Lease.Status.ACTIVE)
        invoices = Invoice.objects.filter(lease__unit__property_id__in=prop_ids)

        total_units = units.count()
        vacant_units = units.filter(status=Unit.Status.VACANT).count()
        occupied_units = units.filter(status=Unit.Status.OCCUPIED).count()

        this_month = timezone.now().date().replace(day=1)
        monthly_collected = Payment.objects.filter(
            invoice__lease__unit__property_id__in=prop_ids,
            status=Payment.Status.CONFIRMED,
            paid_at__date__gte=this_month,
        ).aggregate(total=Sum("amount"))["total"] or 0

        overdue_count = invoices.filter(status=Invoice.Status.OVERDUE).count()
        overdue_amount = invoices.filter(status=Invoice.Status.OVERDUE).aggregate(
            total=Sum("amount_due") - Sum("amount_paid")
        )["total"] or 0

        return Response({
            "properties": props.count(),
            "total_units": total_units,
            "occupied_units": occupied_units,
            "vacant_units": vacant_units,
            "occupancy_rate": round(occupied_units / total_units * 100, 1) if total_units else 0,
            "active_leases": leases.count(),
            "monthly_collected_kes": monthly_collected,
            "overdue_invoices": overdue_count,
            "overdue_amount_kes": overdue_amount,
        })


class MpesaSTKPushView(APIView):
    """
    POST /api/v1/payments/stk/push/
    Initiate an STK Push prompt on the tenant's phone.
    Body: { invoice_id }
    The tenant's phone and amount are derived from the invoice/lease.
    Landlords can also push on behalf of a tenant by passing { invoice_id, phone }.
    """
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [__import__('apps.core.throttles', fromlist=['STKPushThrottle']).STKPushThrottle]

    def post(self, request):
        from .mpesa import stk_push
        from apps.core.utils.phone import normalize_phone

        invoice_id = request.data.get("invoice_id")
        if not invoice_id:
            return Response({"error": "invoice_id is required."}, status=400)

        try:
            invoice = _invoice_qs_for_user(request.user).select_related(
                "lease__tenant", "lease__unit"
            ).get(id=invoice_id)
        except Invoice.DoesNotExist:
            return Response({"error": "Invoice not found."}, status=404)

        if invoice.status == Invoice.Status.PAID:
            return Response({"error": "Invoice is already fully paid."}, status=400)

        # Block duplicate pushes — only one pending STK request per invoice at a time
        existing = MpesaSTKRequest.objects.filter(
            invoice=invoice,
            status=MpesaSTKRequest.Status.PENDING,
        ).first()
        if existing:
            return Response({
                "error": "An STK Push is already pending for this invoice. "
                         "Please complete or wait for it to expire before retrying.",
                "checkout_request_id": existing.checkout_request_id,
            }, status=400)

        # Determine phone — tenant pays themselves; landlord can override
        if request.user.is_tenant:
            phone_e164 = request.user.phone_number
        else:
            phone_raw = request.data.get("phone", invoice.lease.tenant.phone_number)
            phone_e164 = normalize_phone(str(phone_raw))

        # Daraja requires 2547XXXXXXXX (no + prefix)
        phone_daraja = phone_e164.lstrip("+")

        # Amount must be integer
        amount_int = int(invoice.balance)
        if amount_int <= 0:
            return Response({"error": "Invoice balance is zero."}, status=400)

        account_ref = invoice.lease.unit.unit_number[:12]
        description = "Rent"

        try:
            result = stk_push(
                phone=phone_daraja,
                amount=amount_int,
                account_ref=account_ref,
                description=description,
            )
        except Exception as e:
            logger.error("STK Push failed for invoice %s: %s", invoice_id, e)
            return Response({"error": f"STK Push failed: {e}"}, status=502)

        # Persist the request for callback matching
        MpesaSTKRequest.objects.create(
            checkout_request_id=result["CheckoutRequestID"],
            merchant_request_id=result["MerchantRequestID"],
            phone=phone_daraja,
            amount=invoice.balance,
            account_ref=account_ref,
            invoice=invoice,
        )

        return Response({
            "message": "STK Push sent. Check your phone for the M-Pesa prompt.",
            "checkout_request_id": result["CheckoutRequestID"],
        }, status=status.HTTP_200_OK)


class MpesaSTKCallbackView(APIView):
    """
    POST /api/v1/payments/stk/callback/
    Webhook called by Safaricom after the customer completes or cancels the prompt.
    Must return HTTP 200 immediately — all processing is done in Celery.
    Note: URL must not contain 'mpesa' or 'safaricom' in the domain.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [__import__('apps.core.throttles', fromlist=['MpesaWebhookThrottle']).MpesaWebhookThrottle]

    def post(self, request):
        logger.info("STK callback received: %s", request.data)
        from .tasks import process_stk_callback
        process_stk_callback.delay(request.data)
        return Response({"ResultCode": 0, "ResultDesc": "Accepted"})


class MpesaSTKStatusView(APIView):
    """
    GET /api/v1/payments/stk/status/?checkout_request_id=ws_CO_xxx
    Poll the status of a pending STK Push from the mobile app.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        checkout_id = request.query_params.get("checkout_request_id", "").strip()
        if not checkout_id:
            return Response({"error": "checkout_request_id is required."}, status=400)

        try:
            req = MpesaSTKRequest.objects.get(checkout_request_id=checkout_id)
        except MpesaSTKRequest.DoesNotExist:
            return Response({"error": "Request not found."}, status=404)

        return Response({
            "checkout_request_id": req.checkout_request_id,
            "status": req.status,
            "result_code": req.result_code,
            "result_desc": req.result_desc,
            "mpesa_receipt_number": req.mpesa_receipt_number,
            "amount": req.amount,
        })


class MpesaC2BValidateView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        logger.info("M-Pesa C2B validation: %s", request.data)
        return Response({"ResultCode": 0, "ResultDesc": "Accepted"})


class MpesaC2BConfirmView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        data = request.data
        logger.info("M-Pesa C2B confirmation: %s", data)

        receipt_number = data.get("TransID", "")
        amount = data.get("TransAmount", 0)
        account_ref = data.get("BillRefNumber", "").strip().upper()
        phone = data.get("MSISDN", "")

        idempotency_key = make_idempotency_key(receipt_number)

        if Payment.objects.filter(idempotency_key=idempotency_key).exists():
            logger.warning("Duplicate M-Pesa webhook ignored: %s", receipt_number)
            return Response({"ResultCode": 0, "ResultDesc": "OK"})

        from .tasks import process_mpesa_payment
        process_mpesa_payment.delay(
            receipt_number=receipt_number,
            amount=float(amount),
            account_ref=account_ref,
            phone=phone,
            idempotency_key=idempotency_key,
        )

        return Response({"ResultCode": 0, "ResultDesc": "OK"})
