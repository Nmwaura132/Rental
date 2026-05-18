import logging
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from .models import Lease, MaintenanceRequest, MaintenanceNote
from .serializers import LeaseSerializer, MaintenanceRequestSerializer, MaintenanceNoteSerializer

logger = logging.getLogger(__name__)


class LeaseViewSet(viewsets.ModelViewSet):
    serializer_class = LeaseSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ["status", "tenant", "unit"]
    queryset = Lease.objects.none()  # for drf-spectacular schema introspection

    # WHY: unit-status sync used to live here AND in apps.tenants.signals.sync_unit_status.
    # Two sources of truth on the same write path is a maintenance trap — if either
    # changes its logic, drift is invisible. The signal handles every Lease.save()
    # (create + update via the API or admin or shell), so it stays as the single
    # source of truth. Do not re-add perform_create / perform_update hooks.

    def get_queryset(self):
        user = self.request.user
        if user.is_landlord:
            return Lease.objects.filter(
                unit__property__owner=user
            ).select_related("tenant", "unit", "unit__property", "unit__property__owner")
        if user.is_caretaker:
            return Lease.objects.filter(
                unit__property__caretaker=user
            ).select_related("tenant", "unit", "unit__property", "unit__property__owner")
        return Lease.objects.filter(tenant=user).select_related("unit", "unit__property", "unit__property__owner")

    @action(detail=True, methods=["post"], url_path="send-lease")
    def send_lease(self, request, pk=None):
        """
        Generate a Kenya-compliant lease PDF, save to MinIO, optionally SMS the tenant.
        Returns the download URL.
        """
        from .lease_pdf import generate_lease_pdf
        from django.core.files.base import ContentFile
        from django.conf import settings
        import boto3
        from botocore.client import Config

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
            s3 = boto3.client(
                "s3",
                endpoint_url=settings.AWS_S3_ENDPOINT_URL,
                aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
                aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
                config=Config(signature_version="s3v4"),
                region_name="us-east-1",
            )
            bucket = settings.AWS_STORAGE_BUCKET_NAME
            s3.put_object(
                Bucket=bucket,
                Key=filename,
                Body=pdf_bytes,
                ContentType="application/pdf",
                ContentDisposition=f'attachment; filename="lease_{lease.id}.pdf"',
            )
            # Build public URL (MinIO public bucket)
            endpoint = settings.AWS_S3_ENDPOINT_URL.rstrip("/")
            pdf_url = f"{endpoint}/{bucket}/{filename}"
        except Exception:
            # WHY: boto3 errors include endpoint URL + bucket name — never expose.
            logger.exception("MinIO upload failed for lease %s", lease.id)
            return Response(
                {"detail": "File storage failed. Please try again or contact support."},
                status=500,
            )

        # ── 3. Save URL on the lease (notes field as lightweight store) ───────
        lease.notes = (lease.notes or "") + f"\n[Lease PDF] {pdf_url}"
        lease.save(update_fields=["notes"])

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
