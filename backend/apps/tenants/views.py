import logging

from django.utils import timezone
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from apps.core.permissions import IsLandlordOrCaretaker
from apps.notifications.tasks import send_sms
from apps.payments.services import create_move_in_invoice
from .models import Tenancy, MaintenanceRequest, MaintenanceNote
from .notice import vacate_by
from .serializers import TenancySerializer, MaintenanceRequestSerializer, MaintenanceNoteSerializer

logger = logging.getLogger(__name__)

def _validate_managed_tenant(user, tenant):
    if tenant.created_by_id == user.id:
        return
    if user.is_landlord and tenant.tenancies.filter(
        unit__property__owner=user
    ).exists():
        return
    if user.is_caretaker and tenant.tenancies.filter(
        unit__property__caretaker=user
    ).exists():
        return
    raise PermissionDenied("You cannot create tenancies for this tenant.")


class TenancyViewSet(viewsets.ModelViewSet):
    serializer_class = TenancySerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "tenant", "unit"]
    queryset = Tenancy.objects.none()  # for drf-spectacular schema introspection

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy", "send_tenancy"}:
            return [IsLandlordOrCaretaker()]
        return super().get_permissions()

    # WHY: unit-status sync used to live here AND in apps.tenants.signals.sync_unit_status.
    # Two sources of truth on the same write path is a maintenance trap — if either
    # changes its logic, drift is invisible. The signal handles every Tenancy.save()
    # (create + update via the API or admin or shell), so it stays as the single
    # source of truth. Do not re-add perform_create / perform_update hooks.

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            queryset = Tenancy.objects.filter(
                unit__property__owner=user
            ).select_related("tenant", "unit", "unit__property", "unit__property__owner")
        elif user.is_caretaker:
            queryset = Tenancy.objects.filter(
                unit__property__caretaker=user
            ).select_related("tenant", "unit", "unit__property", "unit__property__owner")
        else:
            queryset = Tenancy.objects.filter(tenant=user).select_related(
                "unit", "unit__property", "unit__property__owner"
            )
        property_id = self.request.query_params.get("property")
        if property_id:
            queryset = queryset.filter(unit__property_id=property_id)
        return queryset

    def perform_create(self, serializer):
        unit = serializer.validated_data["unit"]
        tenant = serializer.validated_data["tenant"]
        user = self.request.user
        if user.is_landlord and unit.property.owner_id != user.id:
            raise PermissionDenied("You cannot create tenancies for this unit.")
        if user.is_caretaker and unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot create tenancies for this unit.")
        _validate_managed_tenant(user, tenant)
        tenancy = serializer.save()

        # WHY the first invoice is raised here and not in the signal beside
        # sync_unit_status: the signal fires on every Tenancy.save() anywhere,
        # fixtures and shell writes included, and would collide with any invoice
        # already made for the same (tenancy, period_start). Billing is also a
        # deliberate act by the landlord, not an occupancy invariant.
        if tenancy.status == Tenancy.Status.ACTIVE:
            try:
                create_move_in_invoice(tenancy)
            except Exception:
                # The tenancy is saved and sound; failing the request would
                # throw it away over a billing problem the landlord can fix by
                # raising the invoice by hand.
                logger.exception("Move-in invoice failed for tenancy %s", tenancy.pk)

    def perform_update(self, serializer):
        unit = serializer.validated_data.get("unit", serializer.instance.unit)
        tenant = serializer.validated_data.get("tenant", serializer.instance.tenant)
        user = self.request.user
        if user.is_landlord and unit.property.owner_id != user.id:
            raise PermissionDenied("You cannot move tenancies to this unit.")
        if user.is_caretaker and unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot move tenancies to this unit.")
        _validate_managed_tenant(user, tenant)
        serializer.save()

    def destroy(self, request, *args, **kwargs):
        return Response(
            {"error": "Tenancies are legal records and cannot be deleted."},
            status=status.HTTP_405_METHOD_NOT_ALLOWED,
        )

    @action(detail=True, methods=["post"], url_path="give-notice")
    def give_notice(self, request, pk=None):
        """Written notice to end the tenancy, from the tenant or the landlord.

        POST body: {"reason": "..."} — kept verbatim as the written record. The
        landlord must give one; a tenant may leave it out. The date the tenant
        must be out by is worked out from the agreement (see notice.vacate_by)
        and never accepted from the client, so the notice period cannot be
        shortened by editing the request.
        """
        tenancy = self.get_object()
        user = request.user
        by_tenant = tenancy.tenant_id == user.id
        by_landlord = tenancy.unit.property.owner_id == user.id

        # The agreement lets either party end the tenancy. A caretaker manages
        # the building but is not a party to it, so cannot.
        if not (by_tenant or by_landlord):
            return Response(
                {"error": "Only the tenant or the landlord can give notice on this tenancy."},
                status=status.HTTP_403_FORBIDDEN,
            )

        if tenancy.status != Tenancy.Status.ACTIVE:
            return Response(
                {"error": "This tenancy is no longer active."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if tenancy.has_notice:
            return Response(
                {
                    "error": "Notice was already given on "
                    f"{tenancy.notice_given_at.date().isoformat()}.",
                    "notice_effective_date": tenancy.notice_effective_date,
                },
                status=status.HTTP_409_CONFLICT,
            )

        reason = (request.data.get("reason") or "").strip()[:2000]
        if by_landlord and not reason:
            return Response(
                {"error": "Give the tenant a reason for ending the tenancy."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # WHY localdate() and not now.date(): now.date() is the UTC calendar
        # date. Kenya is UTC+3, so for the first three hours of every local day
        # the UTC date is still yesterday, which could put a notice given after
        # midnight on the wrong side of a month end.
        tenancy.notice_given_at = timezone.now()
        tenancy.notice_effective_date = vacate_by(timezone.localdate())
        tenancy.notice_reason = reason
        tenancy.notice_given_by = user
        tenancy.save(
            update_fields=[
                "notice_given_at", "notice_effective_date", "notice_reason", "notice_given_by",
            ]
        )

        tenant = tenancy.tenant
        unit = tenancy.unit
        vacate_on = tenancy.notice_effective_date.strftime("%d %b %Y")
        if by_tenant:
            send_sms.delay(
                unit.property.owner_id,
                f"{tenant.first_name} {tenant.last_name} has given notice on "
                f"{unit.property.name} unit {unit.unit_number}. Vacating by {vacate_on}.",
            )
            message = f"Notice given. You are expected to vacate by {vacate_on}."
        else:
            send_sms.delay(
                tenant.id,
                f"Dear {tenant.first_name}, your landlord has given notice ending your "
                f"tenancy of {unit.property.name} Unit {unit.unit_number}. Please vacate "
                f"by {vacate_on}. Reason: {reason}",
            )
            message = f"Notice given. {tenant.first_name} must vacate by {vacate_on}."

        return Response(
            {
                "message": message,
                "notice_given_at": tenancy.notice_given_at,
                "notice_effective_date": tenancy.notice_effective_date,
                "notice_given_by": user.id,
            },
            status=status.HTTP_200_OK,
        )

    @action(detail=True, methods=["get", "post"], url_path="settlement")
    def settlement(self, request, pk=None):
        """The deposit settlement at move-out.

        GET  — the settlement if made, otherwise the figures to start from.
               The tenant may read their own.
        POST — the landlord settles: {"deductions": [{"description", "amount"}],
               "forfeited": bool, "notes": str}. Once only.
        """
        from django.core.exceptions import ValidationError as DjangoValidationError

        from . import settlement as deposit
        from .serializers import DepositSettlementSerializer

        tenancy = self.get_object()
        is_owner = tenancy.unit.property.owner_id == request.user.id

        if request.method == "GET":
            if not (is_owner or tenancy.tenant_id == request.user.id):
                return Response({"error": "Not permitted."}, status=status.HTTP_403_FORBIDDEN)
            existing = getattr(tenancy, "deposit_settlement", None)
            if existing:
                return Response({"settled": True, **DepositSettlementSerializer(existing).data})
            return Response({"settled": False, **deposit.preview(tenancy)})

        # Money leaves the landlord's hands here, so only the landlord decides it.
        if not is_owner:
            return Response(
                {"error": "Only the landlord can settle the deposit."},
                status=status.HTTP_403_FORBIDDEN,
            )
        try:
            result = deposit.settle(
                tenancy,
                by=request.user,
                deductions=request.data.get("deductions") or [],
                forfeited=bool(request.data.get("forfeited")),
                notes=request.data.get("notes") or "",
            )
        except DjangoValidationError as exc:
            return Response({"error": exc.messages[0]}, status=status.HTTP_400_BAD_REQUEST)
        return Response(
            {"settled": True, **DepositSettlementSerializer(result).data},
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["post"], url_path="settlement/refund")
    def settlement_refund(self, request, pk=None):
        """Record that the refund was paid: {"method": "cash|mpesa|bank", "reference": ""}."""
        from django.core.exceptions import ValidationError as DjangoValidationError

        from . import settlement as deposit
        from .serializers import DepositSettlementSerializer

        tenancy = self.get_object()
        if tenancy.unit.property.owner_id != request.user.id:
            return Response(
                {"error": "Only the landlord can record the refund."},
                status=status.HTTP_403_FORBIDDEN,
            )
        existing = getattr(tenancy, "deposit_settlement", None)
        if existing is None:
            return Response({"error": "Settle the deposit first."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            deposit.mark_refunded(
                existing,
                method=request.data.get("method"),
                reference=request.data.get("reference") or "",
            )
        except DjangoValidationError as exc:
            return Response({"error": exc.messages[0]}, status=status.HTTP_400_BAD_REQUEST)
        return Response({"settled": True, **DepositSettlementSerializer(existing).data})

    @action(detail=True, methods=["post"], url_path="send-tenancy")
    def send_tenancy(self, request, pk=None):
        """
        Generate a Kenya-compliant tenancy PDF, save to MinIO, optionally SMS the tenant.
        Returns the download URL.
        """
        from .tenancy_pdf import generate_tenancy_pdf
        from django.conf import settings
        from apps.core.private_files import private_file_url, upload_private_file

        tenancy = self.get_object()

        # ── 1. Generate PDF ───────────────────────────────────────────────────
        try:
            pdf_bytes = generate_tenancy_pdf(tenancy)
        except Exception:
            # WHY: don't echo reportlab/internal exception text to clients.
            logger.exception("PDF generation failed for tenancy %s", tenancy.id)
            return Response(
                {"detail": "Tenancy PDF generation failed. Please try again or contact support."},
                status=500,
            )

        # ── 2. Upload to MinIO ────────────────────────────────────────────────
        filename = f"tenancies/tenancy_{tenancy.id}_{tenancy.tenant.phone_number.replace('+', '')}.pdf"
        try:
            stored_key = upload_private_file(
                filename,
                pdf_bytes,
                "application/pdf",
                content_disposition=f'attachment; filename="tenancy_{tenancy.id}.pdf"',
            )
            pdf_url = private_file_url(stored_key)
        except Exception:
            # WHY: boto3 errors include endpoint URL + bucket name — never expose.
            logger.exception("MinIO upload failed for tenancy %s", tenancy.id)
            return Response(
                {"detail": "File storage failed. Please try again or contact support."},
                status=500,
            )

        # ── 3. Save URL on the tenancy (notes field as lightweight store) ───────
        tenancy.document_key = stored_key
        tenancy.save(update_fields=["document_key"])

        # ── 4. SMS the tenant with the download link ──────────────────────────
        sms_sent = False
        try:
            import africastalking
            at_username = getattr(settings, "AT_USERNAME", "sandbox")
            at_api_key = getattr(settings, "AT_API_KEY", "")
            if at_api_key:
                africastalking.initialize(at_username, at_api_key)
                sms = africastalking.SMS
                tenant_name = tenancy.tenant.first_name
                message = (
                    f"Dear {tenant_name}, your tenancy agreement for "
                    f"Unit {tenancy.unit.unit_number}, {tenancy.unit.property.name} "
                    f"is ready. Download: {pdf_url}"
                )
                sms.send(message, [tenancy.tenant.phone_number])
                sms_sent = True
        except Exception as e:
            logger.warning("SMS send failed for tenancy %s: %s", tenancy.id, e)

        # ── 5. WhatsApp delivery (if enabled) ────────────────────────────────
        whatsapp_queued = False
        if getattr(settings, "WHATSAPP_ENABLED", False):
            try:
                from apps.notifications.tasks import send_whatsapp
                wa_msg = (
                    f"Dear {tenancy.tenant.first_name}, your tenancy agreement for "
                    f"Unit {tenancy.unit.unit_number}, {tenancy.unit.property.name} "
                    f"is attached. Please review and keep for your records."
                )
                send_whatsapp.delay(tenancy.tenant.id, wa_msg, media_url=pdf_url)
                whatsapp_queued = True
            except Exception as e:
                logger.warning("WhatsApp dispatch failed for tenancy %s: %s", tenancy.id, e)

        return Response({
            "pdf_url": pdf_url,
            "sms_sent": sms_sent,
            "whatsapp_queued": whatsapp_queued,
            "message": "Tenancy PDF generated and saved." + (" SMS sent to tenant." if sms_sent else " SMS could not be sent."),
        })


class MaintenanceRequestViewSet(viewsets.ModelViewSet):
    serializer_class = MaintenanceRequestSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "priority"]
    queryset = MaintenanceRequest.objects.none()  # for drf-spectacular schema introspection

    def get_permissions(self):
        if self.action in {"update", "partial_update", "destroy"}:
            return [IsLandlordOrCaretaker()]
        return super().get_permissions()

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return MaintenanceRequest.objects.filter(
                tenancy__unit__property__owner=user
            ).select_related("tenancy__tenant", "tenancy__unit")
        if user.is_caretaker:
            return MaintenanceRequest.objects.filter(
                tenancy__unit__property__caretaker=user
            ).select_related("tenancy__tenant", "tenancy__unit")
        return MaintenanceRequest.objects.filter(tenancy__tenant=user).select_related("tenancy__unit__property")

    def perform_create(self, serializer):
        tenancy = serializer.validated_data["tenancy"]
        user = self.request.user
        if user.is_tenant and tenancy.tenant_id != user.id:
            raise PermissionDenied("You cannot create requests for this tenancy.")
        if user.is_landlord and tenancy.unit.property.owner_id != user.id:
            raise PermissionDenied("You cannot create requests for this tenancy.")
        if user.is_caretaker and tenancy.unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot create requests for this tenancy.")
        serializer.save()

    @action(detail=True, methods=["get", "post"], url_path="notes")
    def notes(self, request, pk=None):
        mr = self.get_object()
        if request.method == "GET":
            qs = mr.notes.select_related("author")
            return Response(MaintenanceNoteSerializer(qs, many=True).data)
        serializer = MaintenanceNoteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(request=mr, author=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)
