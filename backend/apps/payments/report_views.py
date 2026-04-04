"""
ReportsView — generates financial PDFs and uploads them to MinIO.
GET /api/v1/payments/reports/?type=<pnl|aged|ledger|rent_roll>&...
"""
import logging
from datetime import date

import boto3
from botocore.config import Config
from django.conf import settings
from django.utils import timezone
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

logger = logging.getLogger(__name__)


def _upload_pdf(pdf_bytes: bytes, key: str) -> str:
    """Upload PDF bytes to MinIO; return public URL."""
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
        Key=key,
        Body=pdf_bytes,
        ContentType="application/pdf",
        ContentDisposition=f'inline; filename="{key.split("/")[-1]}"',
    )
    endpoint = settings.AWS_S3_ENDPOINT_URL.rstrip("/")
    return f"{endpoint}/{bucket}/{key}"


class ReportsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        report_type = request.query_params.get("type", "").strip()
        if not report_type:
            return Response({"error": "type is required (pnl, aged, ledger, rent_roll)."}, status=400)

        dispatch = {
            "pnl": self._pnl,
            "aged": self._aged,
            "ledger": self._ledger,
            "rent_roll": self._rent_roll,
        }
        handler = dispatch.get(report_type)
        if not handler:
            return Response({"error": f"Unknown report type '{report_type}'."}, status=400)

        return handler(request)

    # ── helpers ──────────────────────────────────────────────────────────────

    def _get_property(self, request):
        """Resolve property_id from query params, scoped to the requesting user."""
        from apps.properties.models import Property
        prop_id = request.query_params.get("property")
        if not prop_id:
            return None, Response({"error": "property is required."}, status=400)
        user = request.user
        try:
            if user.is_landlord:
                prop = Property.objects.get(id=prop_id, owner=user)
            elif user.is_caretaker:
                prop = Property.objects.get(id=prop_id, caretaker=user)
            else:
                return None, Response({"error": "Only landlords and caretakers can access property reports."}, status=403)
        except Property.DoesNotExist:
            return None, Response({"error": "Property not found."}, status=404)
        return prop, None

    def _get_lease(self, request):
        """Resolve lease_id, scoped to the requesting user."""
        from apps.tenants.models import Lease
        lease_id = request.query_params.get("lease")
        if not lease_id:
            return None, Response({"error": "lease is required."}, status=400)
        user = request.user
        try:
            if user.is_tenant:
                lease = Lease.objects.select_related(
                    'unit__property', 'tenant'
                ).get(id=lease_id, tenant=user)
            elif user.is_landlord:
                lease = Lease.objects.select_related(
                    'unit__property', 'tenant'
                ).get(id=lease_id, unit__property__owner=user)
            elif user.is_caretaker:
                lease = Lease.objects.select_related(
                    'unit__property', 'tenant'
                ).get(id=lease_id, unit__property__caretaker=user)
            else:
                return None, Response({"error": "Permission denied."}, status=403)
        except Lease.DoesNotExist:
            return None, Response({"error": "Lease not found."}, status=404)
        return lease, None

    # ── report handlers ───────────────────────────────────────────────────────

    def _pnl(self, request):
        prop, err = self._get_property(request)
        if err:
            return err

        try:
            year = int(request.query_params.get("year", date.today().year))
            month = int(request.query_params.get("month", date.today().month))
            if not (1 <= month <= 12):
                raise ValueError
        except (TypeError, ValueError):
            return Response({"error": "year and month must be valid integers."}, status=400)

        from .reports import generate_monthly_pnl
        try:
            pdf_bytes = generate_monthly_pnl(prop, year, month)
        except Exception as e:
            logger.exception("P&L PDF generation failed")
            return Response({"error": f"PDF generation failed: {e}"}, status=500)

        import calendar
        month_label = date(year, month, 1).strftime('%Y-%m')
        key = f"reports/pnl/{prop.id}/{month_label}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception as e:
            logger.exception("MinIO upload failed for P&L report")
            return Response({"error": f"File upload failed: {e}"}, status=500)

        return Response({
            "pdf_url": pdf_url,
            "generated_at": timezone.now().isoformat(),
            "summary": {
                "property": prop.name,
                "year": year,
                "month": month,
            },
        })

    def _aged(self, request):
        prop, err = self._get_property(request)
        if err:
            return err

        from .reports import generate_aged_receivables
        try:
            pdf_bytes = generate_aged_receivables(prop)
        except Exception as e:
            logger.exception("Aged receivables PDF generation failed")
            return Response({"error": f"PDF generation failed: {e}"}, status=500)

        today = date.today().strftime('%Y-%m-%d')
        key = f"reports/aged/{prop.id}/{today}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception as e:
            logger.exception("MinIO upload failed for aged receivables report")
            return Response({"error": f"File upload failed: {e}"}, status=500)

        return Response({
            "pdf_url": pdf_url,
            "generated_at": timezone.now().isoformat(),
            "summary": {"property": prop.name},
        })

    def _ledger(self, request):
        lease, err = self._get_lease(request)
        if err:
            return err

        date_from_str = request.query_params.get("date_from")
        date_to_str = request.query_params.get("date_to")
        try:
            date_from = date.fromisoformat(date_from_str) if date_from_str else date.today().replace(day=1)
            date_to = date.fromisoformat(date_to_str) if date_to_str else date.today()
        except ValueError:
            return Response({"error": "date_from and date_to must be ISO dates (YYYY-MM-DD)."}, status=400)

        from .reports import generate_tenant_ledger
        try:
            pdf_bytes = generate_tenant_ledger(lease, date_from, date_to)
        except Exception as e:
            logger.exception("Tenant ledger PDF generation failed")
            return Response({"error": f"PDF generation failed: {e}"}, status=500)

        key = f"reports/ledger/{lease.id}/{date_from}_{date_to}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception as e:
            logger.exception("MinIO upload failed for ledger report")
            return Response({"error": f"File upload failed: {e}"}, status=500)

        return Response({
            "pdf_url": pdf_url,
            "generated_at": timezone.now().isoformat(),
            "summary": {
                "tenant": lease.tenant.get_full_name(),
                "unit": lease.unit.unit_number,
                "date_from": date_from.isoformat(),
                "date_to": date_to.isoformat(),
            },
        })

    def _rent_roll(self, request):
        prop, err = self._get_property(request)
        if err:
            return err

        from .reports import generate_rent_roll
        try:
            pdf_bytes = generate_rent_roll(prop)
        except Exception as e:
            logger.exception("Rent roll PDF generation failed")
            return Response({"error": f"PDF generation failed: {e}"}, status=500)

        today = date.today().strftime('%Y-%m-%d')
        key = f"reports/rent_roll/{prop.id}/{today}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception as e:
            logger.exception("MinIO upload failed for rent roll report")
            return Response({"error": f"File upload failed: {e}"}, status=500)

        return Response({
            "pdf_url": pdf_url,
            "generated_at": timezone.now().isoformat(),
            "summary": {"property": prop.name},
        })
