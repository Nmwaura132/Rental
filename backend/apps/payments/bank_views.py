"""
Bank payment integration views.

Endpoints:
  POST /api/v1/payments/bank/kcb/ipn/       – KCB Buni IPN webhook
  POST /api/v1/payments/bank/equity/ipn/    – Equity Jenga IPN webhook
  POST /api/v1/payments/bank/equity/poll/   – Manually trigger Equity statement poll
  GET  /api/v1/payments/bank/notifications/ – List bank notifications (landlord)
  POST /api/v1/payments/bank/notifications/<id>/match/ – Manually match to invoice
"""
import hashlib
import hmac
import logging
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.utils import timezone as dj_timezone
from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.pagination import PageNumberPagination
from drf_spectacular.utils import extend_schema
from django.db.models import Q

from apps.core.permissions import IsLandlord
from apps.properties.models import Unit
from .models import BankPaymentNotification, Invoice, Payment
from .bank_reconcile import reconcile_bank_notification

logger = logging.getLogger(__name__)


# ─── Serializers ──────────────────────────────────────────────────────────────

class BankNotificationSerializer(serializers.ModelSerializer):
    bank_display = serializers.CharField(source="get_bank_display", read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)
    matched_invoice = serializers.SerializerMethodField()

    class Meta:
        model = BankPaymentNotification
        fields = [
            "id", "bank", "bank_display", "transaction_ref", "amount",
            "payer_name", "payer_account", "payment_ref",
            "credited_at", "status", "status_display",
            "matched_invoice", "received_at",
        ]

    def get_matched_invoice(self, obj):
        if obj.payment and obj.payment.invoice:
            inv = obj.payment.invoice
            return {"id": inv.id, "invoice_number": inv.invoice_number}
        return None


# ─── KCB Buni IPN ─────────────────────────────────────────────────────────────

@extend_schema(exclude=True)  # bank IPN webhook
class KCBIPNView(APIView):
    """
    POST /api/v1/payments/bank/kcb/ipn/

    KCB Buni sends a POST for every credit on the registered account.
    Expected payload (mirrors Daraja C2B Confirm):
      {
        "TransactionType": "Pay Bill",
        "TransID": "RLJ3KLJ4KL",
        "TransTime": "20250101120000",
        "TransAmount": "15000.00",
        "BusinessShortCode": "123456",
        "BillRefNumber": "UNIT101",       ← what tenant typed as reference
        "MSISDN": "254712345678",
        "FirstName": "John",
        "MiddleName": "",
        "LastName": "Doe"
      }

    Signature: KCB sends X-KCB-Signature = HMAC-SHA256(body, KCB_IPN_SECRET).
    Set KCB_IPN_SECRET in Django settings once you have live credentials.
    """
    permission_classes = [permissions.AllowAny]

    def _verify_signature(self, request) -> bool:
        secret = getattr(settings, "KCB_IPN_SECRET", "")
        if not secret:
            # WHY: fail-CLOSED in production. An unset secret is a misconfiguration,
            # not a license to accept unsigned payments. Allow skip only in DEBUG.
            if settings.DEBUG:
                logger.warning("KCB_IPN_SECRET not set — skipping signature verification (DEBUG only).")
                return True
            logger.error("KCB_IPN_SECRET not set in production — rejecting webhook.")
            return False
        received_sig = request.headers.get("X-KCB-Signature", "")
        expected_sig = hmac.new(
            secret.encode(),
            request.body,
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(received_sig, expected_sig)

    def post(self, request):
        if not self._verify_signature(request):
            logger.warning("KCB IPN: invalid signature — rejected.")
            return Response({"ResultCode": 1, "ResultDesc": "Invalid signature"}, status=403)

        data = request.data
        logger.info("KCB IPN received: %s", data)

        transaction_ref = data.get("TransID", "").strip()
        if not transaction_ref:
            return Response({"ResultCode": 1, "ResultDesc": "Missing TransID"}, status=400)

        # Idempotency — ignore if already stored
        if BankPaymentNotification.objects.filter(
            bank=BankPaymentNotification.Bank.KCB,
            transaction_ref=transaction_ref,
        ).exists():
            logger.info("KCB IPN duplicate ignored: %s", transaction_ref)
            return Response({"ResultCode": 0, "ResultDesc": "OK"})

        try:
            amount_str = str(data.get("TransAmount", "0")).replace(",", "")
            amount = Decimal(amount_str)
            if amount <= 0:
                raise ValueError
            trans_time = data.get("TransTime", "")  # "20250101120000"
            credited_at = (
                datetime.strptime(trans_time, "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)
                if trans_time else dj_timezone.now()
            )
        except (ValueError, TypeError, InvalidOperation) as exc:
            logger.error("KCB IPN parse error: %s — payload: %s", exc, data)
            return Response({"ResultCode": 1, "ResultDesc": "Parse error"}, status=400)

        first = data.get("FirstName", "")
        middle = data.get("MiddleName", "")
        last = data.get("LastName", "")
        payer_name = " ".join(filter(None, [first, middle, last])).strip()

        notification = BankPaymentNotification.objects.create(
            bank=BankPaymentNotification.Bank.KCB,
            transaction_ref=transaction_ref,
            amount=amount,
            payer_name=payer_name,
            payer_account=data.get("MSISDN", ""),
            payment_ref=data.get("BillRefNumber", ""),
            credited_at=credited_at,
            raw_payload=data,
        )

        from .tasks import process_bank_notification
        process_bank_notification.delay(notification.id)

        return Response({"ResultCode": 0, "ResultDesc": "Accepted"})


# ─── Equity Jenga IPN ─────────────────────────────────────────────────────────

@extend_schema(exclude=True)  # bank IPN webhook
class EquityIPNView(APIView):
    """
    POST /api/v1/payments/bank/equity/ipn/

    Equity Jenga POSTs to this URL on successful payment gateway transactions.
    Expected payload:
      {
        "callbackType": "PAYMENT",
        "customer": {
          "name": "John Doe",
          "mobileNumber": "254712345678",
          "reference": "INV-2025-0001"
        },
        "transaction": {
          "date": "2025-01-01T12:00:00",
          "reference": "EQT12345678",
          "paymentMode": "BANK_TRANSFER",
          "amount": 15000,
          "currency": "KES",
          "status": "SUCCESS",
          "remarks": "Rent January"
        }
      }

    Auth: Jenga calls with Basic Auth (username/password you register on JengaHQ).
    Set JENGA_IPN_USERNAME and JENGA_IPN_PASSWORD in Django settings.
    """
    permission_classes = [permissions.AllowAny]

    def _verify_basic_auth(self, request) -> bool:
        username = getattr(settings, "JENGA_IPN_USERNAME", "")
        password = getattr(settings, "JENGA_IPN_PASSWORD", "")
        if not username or not password:
            # WHY: fail-CLOSED in production. See KCBIPNView._verify_signature.
            if settings.DEBUG:
                logger.warning("JENGA_IPN credentials not set — skipping auth (DEBUG only).")
                return True
            logger.error("JENGA_IPN credentials not set in production — rejecting webhook.")
            return False
        import base64
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Basic "):
            return False
        try:
            decoded = base64.b64decode(auth_header[6:]).decode()
            recv_user, recv_pass = decoded.split(":", 1)
            return recv_user == username and recv_pass == password
        except Exception:
            return False

    def post(self, request):
        if not self._verify_basic_auth(request):
            logger.warning("Equity IPN: auth failed — rejected.")
            return Response({"status": "UNAUTHORIZED"}, status=401)

        data = request.data
        logger.info("Equity IPN received: %s", data)

        txn = data.get("transaction", {})
        customer = data.get("customer", {})

        transaction_ref = txn.get("reference", "").strip()
        txn_status = txn.get("status", "").upper()

        if not transaction_ref:
            return Response({"status": "MISSING_REF"}, status=400)

        if txn_status != "SUCCESS":
            logger.info("Equity IPN: non-success status %s for %s — ignored.", txn_status, transaction_ref)
            return Response({"status": "IGNORED"})

        if BankPaymentNotification.objects.filter(
            bank=BankPaymentNotification.Bank.EQUITY,
            transaction_ref=transaction_ref,
        ).exists():
            logger.info("Equity IPN duplicate ignored: %s", transaction_ref)
            return Response({"status": "OK"})

        try:
            amount = Decimal(str(txn.get("amount", 0)))
            if amount <= 0:
                raise ValueError
            date_str = txn.get("date", "")
            credited_at = (
                datetime.fromisoformat(date_str).replace(tzinfo=timezone.utc)
                if date_str else dj_timezone.now()
            )
        except (ValueError, TypeError, InvalidOperation) as exc:
            logger.error("Equity IPN parse error: %s — payload: %s", exc, data)
            return Response({"status": "PARSE_ERROR"}, status=400)

        notification = BankPaymentNotification.objects.create(
            bank=BankPaymentNotification.Bank.EQUITY,
            transaction_ref=transaction_ref,
            amount=amount,
            payer_name=customer.get("name", ""),
            payer_account=customer.get("mobileNumber", ""),
            payment_ref=customer.get("reference", ""),
            credited_at=credited_at,
            raw_payload=data,
        )

        from .tasks import process_bank_notification
        process_bank_notification.delay(notification.id)

        return Response({"status": "OK"})


# ─── Equity Statement Poll ─────────────────────────────────────────────────────

@extend_schema(exclude=True)  # admin-only manual trigger
class EquityStatementPollView(APIView):
    """
    POST /api/v1/payments/bank/equity/poll/
    Trigger an immediate Equity mini-statement pull. Landlords only.
    Useful to catch direct EFTs that didn't come through the Jenga payment gateway.
    Body (optional): { "date_from": "YYYY-MM-DD", "date_to": "YYYY-MM-DD" }
    """
    permission_classes = [IsLandlord]

    def post(self, request):
        date_from = request.data.get("date_from")
        date_to = request.data.get("date_to")

        from .tasks import poll_equity_statement
        poll_equity_statement.delay(date_from=date_from, date_to=date_to)

        return Response({"message": "Equity statement poll queued. Results will appear in notifications."})


# ─── Bank Notification List ────────────────────────────────────────────────────

@extend_schema(exclude=True)
class BankNotificationListView(APIView):
    """
    GET /api/v1/payments/bank/notifications/?status=unmatched&bank=kcb
    List bank payment notifications. Landlords / caretakers only.
    """
    permission_classes = [IsLandlord]

    def get(self, request):
        owned_invoice_refs = Invoice.objects.filter(
            tenancy__unit__property__owner=request.user
        ).values("invoice_number")
        owned_units = Unit.objects.filter(property__owner=request.user)
        owned_unit_refs = owned_units.values("unit_number")
        owned_payment_codes = owned_units.values("payment_code")
        qs = BankPaymentNotification.objects.filter(
            Q(payment__invoice__tenancy__unit__property__owner=request.user)
            | Q(payment_ref__in=owned_invoice_refs)
            | Q(payment_ref__in=owned_unit_refs)
            | Q(payment_ref__in=owned_payment_codes)
        ).distinct()

        status_filter = request.query_params.get("status")
        bank_filter = request.query_params.get("bank")
        if status_filter:
            qs = qs.filter(status=status_filter)
        if bank_filter:
            qs = qs.filter(bank=bank_filter)

        qs = qs.select_related("payment__invoice").order_by("-credited_at")
        paginator = PageNumberPagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response(
            BankNotificationSerializer(page, many=True).data
        )


# ─── Manual Match ─────────────────────────────────────────────────────────────

@extend_schema(exclude=True)
class BankNotificationMatchView(APIView):
    """
    POST /api/v1/payments/bank/notifications/<id>/match/
    Manually link an UNMATCHED notification to a specific invoice.
    Body: { "invoice_id": 42 }
    """
    permission_classes = [IsLandlord]

    def post(self, request, pk):
        owned_invoice_refs = Invoice.objects.filter(
            tenancy__unit__property__owner=request.user
        ).values("invoice_number")
        owned_units = Unit.objects.filter(property__owner=request.user)
        owned_unit_refs = owned_units.values("unit_number")
        owned_payment_codes = owned_units.values("payment_code")
        try:
            notification = BankPaymentNotification.objects.filter(
                Q(payment__invoice__tenancy__unit__property__owner=request.user)
                | Q(payment_ref__in=owned_invoice_refs)
                | Q(payment_ref__in=owned_unit_refs)
                | Q(payment_ref__in=owned_payment_codes)
            ).distinct().get(pk=pk)
        except BankPaymentNotification.DoesNotExist:
            return Response({"error": "Notification not found."}, status=404)

        if notification.status == BankPaymentNotification.Status.MATCHED:
            return Response({"error": "Already matched."}, status=400)

        invoice_id = request.data.get("invoice_id")
        if not invoice_id:
            return Response({"error": "invoice_id is required."}, status=400)

        from .views import _invoice_qs_for_user
        try:
            invoice = _invoice_qs_for_user(request.user).get(id=invoice_id)
        except Invoice.DoesNotExist:
            return Response({"error": "Invoice not found."}, status=404)

        if invoice.status == Invoice.Status.PAID:
            return Response({"error": "Invoice is already fully paid."}, status=400)

        matched = reconcile_bank_notification(notification, invoice_id=invoice.pk)
        if matched:
            return Response({"message": "Matched successfully.", "invoice_number": invoice.invoice_number})
        return Response({"error": "Could not reconcile — check amounts."}, status=400)
