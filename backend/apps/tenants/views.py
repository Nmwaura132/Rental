import logging
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from apps.core.permissions import IsLandlordOrCaretaker
from .models import Lease, MaintenanceRequest, MaintenanceNote
from .serializers import LeaseSerializer, MaintenanceRequestSerializer, MaintenanceNoteSerializer

logger = logging.getLogger(__name__)


def _validate_managed_tenant(user, tenant):
    if tenant.created_by_id == user.id:
        return
    if user.is_landlord and tenant.leases.filter(
        unit__property__owner=user
    ).exists():
        return
    if user.is_caretaker and tenant.leases.filter(
        unit__property__caretaker=user
    ).exists():
        return
    raise PermissionDenied("You cannot create leases for this tenant.")


class LeaseViewSet(viewsets.ModelViewSet):
    serializer_class = LeaseSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "tenant", "unit"]
    queryset = Lease.objects.none()  # for drf-spectacular schema introspection

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy", "send_lease"}:
            return [IsLandlordOrCaretaker()]
        return super().get_permissions()

    # WHY: unit-status sync used to live here AND in apps.tenants.signals.sync_unit_status.
    # Two sources of truth on the same write path is a maintenance trap — if either
    # changes its logic, drift is invisible. The signal handles every Lease.save()
    # (create + update via the API or admin or shell), so it stays as the single
    # source of truth. Do not re-add perform_create / perform_update hooks.

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            queryset = Lease.objects.filter(
                unit__property__owner=user
            ).select_related("tenant", "unit", "unit__property", "unit__property__owner")
        elif user.is_caretaker:
            queryset = Lease.objects.filter(
                unit__property__caretaker=user
            ).select_related("tenant", "unit", "unit__property", "unit__property__owner")
        else:
            queryset = Lease.objects.filter(tenant=user).select_related(
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
            raise PermissionDenied("You cannot create leases for this unit.")
        if user.is_caretaker and unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot create leases for this unit.")
        _validate_managed_tenant(user, tenant)
        serializer.save()

    def perform_update(self, serializer):
        unit = serializer.validated_data.get("unit", serializer.instance.unit)
        tenant = serializer.validated_data.get("tenant", serializer.instance.tenant)
        user = self.request.user
        if user.is_landlord and unit.property.owner_id != user.id:
            raise PermissionDenied("You cannot move leases to this unit.")
        if user.is_caretaker and unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot move leases to this unit.")
        _validate_managed_tenant(user, tenant)
        serializer.save()

    def destroy(self, request, *args, **kwargs):
        return Response(
            {"error": "Leases are legal records and cannot be deleted."},
            status=status.HTTP_405_METHOD_NOT_ALLOWED,
        )

    @action(detail=True, methods=["post"], url_path="send-lease")
    def send_lease(self, request, pk=None):
        """
        Generate a Kenya-compliant lease PDF, save to MinIO, optionally SMS the tenant.
        Returns the download URL.
        """
        from .lease_pdf import generate_lease_pdf
        from django.conf import settings
        from apps.core.private_files import private_file_url, upload_private_file

        lease = self.get_object()

        # ── 1. Generate PDF ───────────────────────────────────────────────────
        try:
            pdf_bytes = generate_lease_pdf(lease)
        except Exception:
            # WHY: don't echo reportlab/internal exception text to clients.
            logger.exception("PDF generation failed for lease %s", lease.id)
            return Response(
                {"detail": "Lease PDF generation failed. Please try again or contact support."},
                status=500,
            )

        # ── 2. Upload to MinIO ────────────────────────────────────────────────
        filename = f"leases/lease_{lease.id}_{lease.tenant.phone_number.replace('+', '')}.pdf"
        try:
            stored_key = upload_private_file(
                filename,
                pdf_bytes,
                "application/pdf",
                content_disposition=f'attachment; filename="lease_{lease.id}.pdf"',
            )
            pdf_url = private_file_url(stored_key)
        except Exception:
            # WHY: boto3 errors include endpoint URL + bucket name — never expose.
            logger.exception("MinIO upload failed for lease %s", lease.id)
            return Response(
                {"detail": "File storage failed. Please try again or contact support."},
                status=500,
            )

        # ── 3. Save URL on the lease (notes field as lightweight store) ───────
        lease.document_key = stored_key
        lease.save(update_fields=["document_key"])

        # ── 4. SMS the tenant with the download link ──────────────────────────
        sms_sent = False
        try:
            import africastalking
            at_username = getattr(settings, "AT_USERNAME", "sandbox")
            at_api_key = getattr(settings, "AT_API_KEY", "")
            if at_api_key:
                africastalking.initialize(at_username, at_api_key)
                sms = africastalking.SMS
                tenant_name = lease.tenant.first_name
                message = (
                    f"Dear {tenant_name}, your tenancy agreement for "
                    f"Unit {lease.unit.unit_number}, {lease.unit.property.name} "
                    f"is ready. Download: {pdf_url}"
                )
                sms.send(message, [lease.tenant.phone_number])
                sms_sent = True
        except Exception as e:
            logger.warning("SMS send failed for lease %s: %s", lease.id, e)

        # ── 5. WhatsApp delivery (if enabled) ────────────────────────────────
        whatsapp_queued = False
        if getattr(settings, "WHATSAPP_ENABLED", False):
            try:
                from apps.notifications.tasks import send_whatsapp
                wa_msg = (
                    f"Dear {lease.tenant.first_name}, your tenancy agreement for "
                    f"Unit {lease.unit.unit_number}, {lease.unit.property.name} "
                    f"is attached. Please review and keep for your records."
                )
                send_whatsapp.delay(lease.tenant.id, wa_msg, media_url=pdf_url)
                whatsapp_queued = True
            except Exception as e:
                logger.warning("WhatsApp dispatch failed for lease %s: %s", lease.id, e)

        return Response({
            "pdf_url": pdf_url,
            "sms_sent": sms_sent,
            "whatsapp_queued": whatsapp_queued,
            "message": "Lease PDF generated and saved." + (" SMS sent to tenant." if sms_sent else " SMS could not be sent."),
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
                lease__unit__property__owner=user
            ).select_related("lease__tenant", "lease__unit")
        if user.is_caretaker:
            return MaintenanceRequest.objects.filter(
                lease__unit__property__caretaker=user
            ).select_related("lease__tenant", "lease__unit")
        return MaintenanceRequest.objects.filter(lease__tenant=user).select_related("lease__unit__property")

    def perform_create(self, serializer):
        lease = serializer.validated_data["lease"]
        user = self.request.user
        if user.is_tenant and lease.tenant_id != user.id:
            raise PermissionDenied("You cannot create requests for this lease.")
        if user.is_landlord and lease.unit.property.owner_id != user.id:
            raise PermissionDenied("You cannot create requests for this lease.")
        if user.is_caretaker and lease.unit.property.caretaker_id != user.id:
            raise PermissionDenied("You cannot create requests for this lease.")
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
