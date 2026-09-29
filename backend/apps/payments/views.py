import logging
import uuid
from decimal import Decimal, InvalidOperation
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from django.db.models import Sum, Count, Q
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView
from drf_spectacular.utils import extend_schema

from apps.core.permissions import IsLandlord
from .models import Invoice, Payment, MpesaSTKRequest
from .serializers import InvoiceSerializer, PaymentSerializer
from .mpesa import make_idempotency_key
from .services import apply_confirmed_payment, apply_credit, how_to_pay

logger = logging.getLogger(__name__)


def _invoice_qs_for_user(user):
    if user.is_landlord:
        return Invoice.objects.filter(tenancy__unit__property__owner=user)
    if user.is_caretaker:
        return Invoice.objects.filter(tenancy__unit__property__caretaker=user)
    return Invoice.objects.filter(tenancy__tenant=user)


def _payment_qs_for_user(user):
    if user.is_landlord:
        return Payment.objects.filter(invoice__tenancy__unit__property__owner=user)
    if user.is_caretaker:
        return Payment.objects.filter(invoice__tenancy__unit__property__caretaker=user)
    return Payment.objects.filter(invoice__tenancy__tenant=user)


class InvoiceViewSet(viewsets.ModelViewSet):
    serializer_class = InvoiceSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["status", "tenancy"]
    queryset = Invoice.objects.none()  # for drf-spectacular schema introspection

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy"}:
            return [IsLandlord()]
        return super().get_permissions()

    def get_queryset(self):
        return _invoice_qs_for_user(self.request.user).select_related(
            "tenancy__tenant", "tenancy__unit"
        ).prefetch_related("line_items", "payments")

    def perform_create(self, serializer):
        tenancy = serializer.validated_data["tenancy"]
        user = self.request.user
        if user.is_landlord and tenancy.unit.property.owner_id != user.id:
            raise PermissionDenied("You cannot create invoices for this tenancy.")
        if user.is_caretaker and tenancy.unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot create invoices for this tenancy.")
        super().perform_create(serializer)
        apply_credit(serializer.instance.tenancy)
        invoice = Invoice.objects.select_related(
            "tenancy__tenant", "tenancy__unit__property"
        ).get(pk=serializer.instance.pk)
        from apps.notifications.tasks import send_sms
        tenant = invoice.tenancy.tenant
        unit = invoice.tenancy.unit
        msg = (
            f"Dear {tenant.first_name}, invoice {invoice.invoice_number} "
            f"for {unit.property.name} Unit {unit.unit_number} "
            f"has been issued. Amount: KES {invoice.amount_due:,.0f}. "
            f"Due: {invoice.due_date.strftime('%d %b %Y')}. "
            f"{how_to_pay(unit)}"
        )
        send_sms.delay(tenant.id, msg)

    def perform_update(self, serializer):
        tenancy = serializer.validated_data.get("tenancy", serializer.instance.tenancy)
        user = self.request.user
        if user.is_landlord and tenancy.unit.property.owner_id != user.id:
            raise PermissionDenied("You cannot move invoices to this tenancy.")
        if user.is_caretaker and tenancy.unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot move invoices to this tenancy.")
        serializer.save()

    def destroy(self, request, *args, **kwargs):
        return Response(
            {"error": "Invoices are financial records and cannot be deleted."},
            status=status.HTTP_405_METHOD_NOT_ALLOWED,
        )

    @action(detail=True, methods=["post"], permission_classes=[IsLandlord])
    def cancel(self, request, pk=None):
        invoice = self.get_object()
        if invoice.payments.exists() or invoice.amount_paid:
            return Response(
                {"error": "An invoice with payments cannot be cancelled."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        invoice.status = Invoice.Status.CANCELLED
        invoice.save(update_fields=["status", "updated_at"])
        return Response(self.get_serializer(invoice).data)

    @action(detail=True, methods=["post"], permission_classes=[IsLandlord])
    def remind(self, request, pk=None):
        """Text the tenant a reminder about this bill — at most once a day.

        WHY limited: reminders already go out by themselves around the due
        date, so this is a nudge for one bill, not a way to text someone
        repeatedly. The limit is per bill, so a tenant with two open bills can
        still be reminded about each.
        """
        from django.core.cache import cache

        from apps.notifications.tasks import send_sms

        invoice = self.get_object()
        if invoice.status not in (
            Invoice.Status.PENDING, Invoice.Status.PARTIALLY_PAID, Invoice.Status.OVERDUE
        ):
            return Response(
                {"error": "There is nothing left to remind them about on this bill."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # add() is atomic: only the first of two quick taps gets through.
        if not cache.add(f"invoice-reminder:{invoice.pk}", 1, timeout=24 * 3600):
            return Response(
                {"error": "A reminder about this bill was already sent in the last 24 hours."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        tenancy = invoice.tenancy
        unit = tenancy.unit
        send_sms.delay(
            tenancy.tenant_id,
            f"Dear {tenancy.tenant.first_name}, a reminder that KES {invoice.balance:,.0f} "
            f"is still due on your {invoice.period_start:%B} bill for "
            f"{unit.property.name} Unit {unit.unit_number}. {how_to_pay(unit)}",
        )
        return Response({"sent": True})


class PaymentViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = PaymentSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["method", "status"]
    queryset = Payment.objects.none()  # for drf-spectacular schema introspection

    def get_queryset(self):
        return (
            _payment_qs_for_user(self.request.user)
            .select_related("invoice__tenancy__tenant", "invoice__tenancy__unit__property")
            .order_by("-paid_at", "-id")
        )

    @action(detail=False, methods=["post"], url_path="record",
            permission_classes=[IsLandlord])
    def record_payment(self, request):
        """
        Manually record a cash or bank payment — landlords only.
        Tenants pay via STK Push. Body: { invoice, method, amount }
        """
        invoice_id = request.data.get("invoice")
        method = request.data.get("method")
        amount = request.data.get("amount")

        allowed_methods = [Payment.Method.CASH, Payment.Method.BANK]
        if method not in [m.value for m in allowed_methods]:
            return Response(
                {"error": f"Method must be one of: {[m.value for m in allowed_methods]}"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # WHY: Decimal(str(...)) is the only safe path for money. float() loses
        # precision (e.g. 1000.10 -> 1000.1000000000001 in IEEE-754) and that drift
        # compounds across additions, breaking partial-payment ledgers.
        try:
            amount = Decimal(str(amount))
            if amount <= 0:
                raise ValueError
        except (TypeError, ValueError, InvalidOperation):
            return Response({"error": "Amount must be a positive number."}, status=status.HTTP_400_BAD_REQUEST)

        bank_fields = {}
        if method == Payment.Method.BANK:
            bank_fields = {
                "bank_name": (request.data.get("bank_name") or "").strip() or None,
                "bank_account": (request.data.get("bank_account") or "").strip() or None,
                "bank_reference": (request.data.get("bank_reference") or "").strip() or None,
                "bank_branch": (request.data.get("bank_branch") or "").strip() or None,
            }

        try:
            invoice = _invoice_qs_for_user(request.user).get(id=invoice_id)

            # WHY only on the manual path: an M-Pesa or bank payment has already
            # happened, so refusing it would lose a real receipt. A figure typed
            # in by hand has not, and one exceeding the balance is a slip or a
            # false entry — and because confirmed payments are immutable, it
            # cannot be corrected afterwards. Sending the excess to the invoice
            # it belongs to also keeps the KRA rent roll honest.
            outstanding = invoice.amount_due - (invoice.amount_paid or Decimal("0"))
            if amount > outstanding:
                return Response(
                    {
                        "error": (
                            f"That is more than this invoice is owed. Outstanding "
                            f"balance is KES {outstanding:,.2f}. Record the excess "
                            f"against the invoice it belongs to."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            payment, _ = apply_confirmed_payment(
                invoice_id=invoice.pk,
                method=method,
                amount=amount,
                idempotency_key=f"{method}:{uuid.uuid4().hex}",
                paid_at=timezone.now(),
                payment_fields=bank_fields,
                # A hand-entered payment is permanent and cannot be edited, so
                # the record has to say who entered it.
                recorded_by=request.user,
            )
        except Invoice.DoesNotExist:
            return Response({"error": "Invoice not found."}, status=status.HTTP_404_NOT_FOUND)
        except DjangoValidationError as exc:
            return Response({"error": exc.messages[0]}, status=status.HTTP_400_BAD_REQUEST)

        return Response(PaymentSerializer(payment).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="etims-receipt",
            permission_classes=[IsLandlord])
    def set_etims_receipt(self, request, pk=None):
        """
        Record the eTIMS receipt number issued for a payment — landlords only.

        WHY a dedicated action rather than making the field writable: a confirmed
        payment is immutable on purpose, and that guarantee protects the money
        fields. The receipt cannot be captured at payment time either — the
        landlord generates it on eTIMS after the rent lands, so it always
        arrives late. This lets that one annotation through and nothing else.
        """
        number = (request.data.get("etims_receipt_number") or "").strip()
        if not number:
            return Response(
                {"error": "An eTIMS receipt number is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(number) > 50:
            return Response(
                {"error": "That receipt number is too long."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            payment = Payment.objects.get(
                pk=pk, invoice__tenancy__unit__property__owner=request.user
            )
        except Payment.DoesNotExist:
            return Response({"error": "Payment not found."}, status=status.HTTP_404_NOT_FOUND)

        payment.etims_receipt_number = number
        payment.save(update_fields=["etims_receipt_number"])
        return Response(PaymentSerializer(payment).data)


@extend_schema(exclude=True)  # WHY: returns ad-hoc dict shaped by user role; document in handoff.md instead
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
        from apps.tenants.models import Tenancy
        user = request.user

        if user.is_tenant:
            from django.conf import settings as django_settings
            # Tenant dashboard: balance, next due date, active tenancy/unit info
            invoices = Invoice.objects.filter(tenancy__tenant=user)
            _bal = invoices.filter(
                status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE, Invoice.Status.PARTIALLY_PAID]
            ).aggregate(due=Sum("amount_due"), paid=Sum("amount_paid"))
            total_balance = (_bal["due"] or 0) - (_bal["paid"] or 0)
            next_invoice = invoices.filter(
                status__in=[Invoice.Status.PENDING, Invoice.Status.OVERDUE]
            ).order_by("due_date").first()
            tenancy = Tenancy.objects.filter(
                tenant=user, status=Tenancy.Status.ACTIVE
            ).select_related("unit__property").first()
            return Response({
                "outstanding_balance": total_balance,
                "next_due_date": next_invoice.due_date if next_invoice else None,
                "next_due_amount": next_invoice.balance if next_invoice else None,
                "unit_number": tenancy.unit.unit_number if tenancy else None,
                "property_name": tenancy.unit.property.name if tenancy else None,
                "monthly_rent": float(tenancy.rent_amount) if tenancy else None,
                "tenancy_start": tenancy.start_date.isoformat() if (tenancy and tenancy.start_date) else None,
                "tenancy_end": tenancy.end_date.isoformat() if (tenancy and tenancy.end_date) else None,
                # The id and notice state let the tenant give — or see they have
                # already given — notice without a second round trip.
                "tenancy_id": tenancy.id if tenancy else None,
                "notice_given_at": tenancy.notice_given_at.isoformat() if (tenancy and tenancy.notice_given_at) else None,
                "notice_effective_date": tenancy.notice_effective_date.isoformat() if (tenancy and tenancy.notice_effective_date) else None,
                "mpesa_paybill": django_settings.RENT_PAYBILL,
            })

        # Landlord / caretaker dashboard
        if user.is_landlord:
            props = Property.objects.filter(owner=user)
        else:
            props = Property.objects.filter(caretaker=user)

        prop_ids = props.values_list("id", flat=True)
        units = Unit.objects.filter(property_id__in=prop_ids)
        tenancies = Tenancy.objects.filter(unit__property_id__in=prop_ids, status=Tenancy.Status.ACTIVE)
        invoices = Invoice.objects.filter(tenancy__unit__property_id__in=prop_ids)

        total_units = units.count()
        vacant_units = units.filter(status=Unit.Status.VACANT).count()
        occupied_units = units.filter(status=Unit.Status.OCCUPIED).count()

        this_month = timezone.now().date().replace(day=1)
        # WHY the deposit is left out: "collected" is money that arrived this
        # month. A deposit applied to arrears at move-out arrived at move-in and
        # was counted then, so counting it again here would count it twice.
        monthly_collected = Payment.objects.filter(
            invoice__tenancy__unit__property_id__in=prop_ids,
            status=Payment.Status.CONFIRMED,
            paid_at__date__gte=this_month,
        ).exclude(method=Payment.Method.DEPOSIT).aggregate(total=Sum("amount"))["total"] or 0

        overdue = invoices.filter(status=Invoice.Status.OVERDUE)
        overdue_count = overdue.count()

        occupancy = {
            "properties": props.count(),
            "total_units": total_units,
            "occupied_units": occupied_units,
            "vacant_units": vacant_units,
            "occupancy_rate": round(occupied_units / total_units * 100, 1) if total_units else 0,
            "active_tenancies": tenancies.count(),
        }

        # WHY a separate payload: the design keeps money from caretakers
        # entirely, and hiding it in the app is not enough while the server
        # still sends it. A caretaker gets their day's work instead.
        if not user.is_landlord:
            return Response({**occupancy, **_caretaker_today(props, tenancies)})

        overdue_amount = overdue.aggregate(
            total=Sum("amount_due") - Sum("amount_paid")
        )["total"] or 0
        oldest = overdue.order_by("due_date").values_list("due_date", flat=True).first()

        # "Of KES 252,000 expected": this month's bills and what has been paid
        # against them, so the percentage means "how much of this month's rent
        # is in", not money that happened to arrive this month for old bills.
        this_months_bills = invoices.filter(period_start=this_month).exclude(
            status=Invoice.Status.CANCELLED
        )
        expected = this_months_bills.aggregate(total=Sum("amount_due"))["total"] or 0
        collected_against = sum(
            (min(b.amount_paid, b.amount_due) for b in this_months_bills), Decimal("0")
        )

        return Response({
            **occupancy,
            "monthly_collected_kes": monthly_collected,
            "expected_this_month_kes": expected,
            "collected_against_expected_kes": collected_against,
            "overdue_invoices": overdue_count,
            "overdue_amount_kes": overdue_amount,
            "oldest_overdue_days": (timezone.localdate() - oldest).days if oldest else None,
        })


def _caretaker_today(props, tenancies):
    """A caretaker's day: meters to read, repairs to see to, people moving."""
    from datetime import timedelta

    from apps.properties.models import MeterReading, PropertyCharge
    from apps.tenants.models import MaintenanceRequest

    today = timezone.localdate()
    period = today.replace(day=1)
    metered = PropertyCharge.objects.filter(
        property__in=props, is_active=True, billing_method=PropertyCharge.BillingMethod.METERED
    )
    readings_left = 0
    for tenancy in tenancies.select_related("unit"):
        for charge in metered:
            if charge.property_id != tenancy.unit.property_id:
                continue
            if not MeterReading.objects.filter(unit=tenancy.unit, charge=charge, period=period).exists():
                readings_left += 1

    open_repairs = MaintenanceRequest.objects.filter(
        tenancy__unit__property__in=props,
        status__in=[MaintenanceRequest.Status.OPEN, MaintenanceRequest.Status.IN_PROGRESS],
    ).count()

    def person(t, when):
        return {
            "unit": t.unit.unit_number,
            "property": t.unit.property.name,
            "tenant": t.tenant.get_full_name(),
            "date": when,
        }

    moving_out = [
        person(t, t.notice_effective_date)
        for t in tenancies.filter(
            notice_effective_date__gte=today,
            notice_effective_date__lte=today + timedelta(days=45),
        ).select_related("unit__property", "tenant").order_by("notice_effective_date")
    ]
    from apps.tenants.models import Tenancy

    arriving = [
        person(t, t.start_date)
        for t in Tenancy.objects.filter(
            unit__property__in=props, status=Tenancy.Status.ACTIVE, start_date__gt=today
        ).select_related("unit__property", "tenant").order_by("start_date")
    ]
    return {
        "readings_left": readings_left,
        "open_repairs": open_repairs,
        "moving_out": moving_out,
        "arriving": arriving,
    }


@extend_schema(exclude=True)  # WHY: documented in handoff.md; ad-hoc body schema
class MpesaSTKPushView(APIView):
    """
    POST /api/v1/payments/stk/push/
    Initiate an STK Push prompt on the tenant's phone.
    Body: { invoice_id }
    The tenant's phone and amount are derived from the invoice/tenancy.
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
                "tenancy__tenant", "tenancy__unit"
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
            phone_raw = request.data.get("phone", invoice.tenancy.tenant.phone_number)
            phone_e164 = normalize_phone(str(phone_raw))

        # Daraja requires 2547XXXXXXXX (no + prefix)
        phone_daraja = phone_e164.lstrip("+")

        # Amount must be integer
        amount_int = int(invoice.balance)
        if amount_int <= 0:
            return Response({"error": "Invoice balance is zero."}, status=400)

        account_ref = invoice.tenancy.unit.payment_code
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


@extend_schema(exclude=True)  # WHY: Safaricom webhook — shape defined by Daraja, not us
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


@extend_schema(exclude=True)
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
            req = MpesaSTKRequest.objects.filter(
                invoice__in=_invoice_qs_for_user(request.user)
            ).get(checkout_request_id=checkout_id)
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


@extend_schema(exclude=True)  # admin-only, no client schema needed
class MpesaRegisterC2BView(APIView):
    """
    POST /api/v1/payments/mpesa/register/
    Trigger C2B URL registration with Daraja. Landlords only.
    Safe to call multiple times — Daraja overwrites with the latest URLs.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if not request.user.is_landlord:
            return Response({"error": "Landlords only."}, status=403)
        from .mpesa import register_c2b_urls
        from django.conf import settings
        missing = [
            k for k in ("MPESA_CONSUMER_KEY", "MPESA_CONSUMER_SECRET",
                        "MPESA_SHORTCODE", "MPESA_PASSKEY", "MPESA_CALLBACK_URL")
            if not getattr(settings, k, "")
        ]
        if missing:
            return Response(
                {"error": f"Missing Daraja settings: {', '.join(missing)}. Fill in .env."},
                status=500,
            )
        try:
            result = register_c2b_urls()
        except Exception as exc:
            logger.error("C2B registration failed: %s", exc)
            return Response({"error": str(exc)}, status=502)

        return Response({
            "message": "C2B URLs registered with Daraja.",
            "confirm_url": f"{settings.MPESA_CALLBACK_URL}confirm/",
            "validate_url": f"{settings.MPESA_CALLBACK_URL}validate/",
            "daraja_response": result,
        })


@extend_schema(exclude=True)  # Safaricom webhook
class MpesaC2BValidateView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        logger.info("M-Pesa C2B validation: %s", request.data)
        return Response({"ResultCode": 0, "ResultDesc": "Accepted"})


@extend_schema(exclude=True)  # Safaricom webhook
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

        # WHY: send amount as a JSON-safe string and let the Celery task parse it
        # to Decimal. Passing float() here corrupts cents for any non-integer KES
        # (Safaricom occasionally returns "100.50" depending on the tariff).
        from .tasks import process_mpesa_payment
        process_mpesa_payment.delay(
            receipt_number=receipt_number,
            amount=str(amount),
            account_ref=account_ref,
            phone=phone,
            idempotency_key=idempotency_key,
        )

        return Response({"ResultCode": 0, "ResultDesc": "OK"})
