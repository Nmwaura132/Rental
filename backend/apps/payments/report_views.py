"""
ReportsView — generates financial PDFs and uploads them to MinIO.
GET /api/v1/payments/reports/?type=<pnl|aged|ledger|rent_roll>&...
"""
import logging
from datetime import date
from decimal import Decimal

from django.utils import timezone
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from drf_spectacular.utils import extend_schema

from apps.core.private_files import private_file_url, upload_private_file

logger = logging.getLogger(__name__)


def _upload_pdf(pdf_bytes: bytes, key: str) -> str:
    stored_key = upload_private_file(
        key,
        pdf_bytes,
        "application/pdf",
        content_disposition=f'inline; filename="{key.split("/")[-1]}"',
    )
    return private_file_url(stored_key)


def _plain(value):
    """Money as strings, the way the rest of the API sends it."""
    if isinstance(value, dict):
        return {k: _plain(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_plain(v) for v in value]
    if isinstance(value, Decimal):
        return str(value)
    return value


@extend_schema(exclude=True)  # WHY: ad-hoc query params; returns PDF URL — document in handoff.md
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
            "statement": self._statement,
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

    def _get_tenancy(self, request):
        """Resolve tenancy_id, scoped to the requesting user."""
        from apps.tenants.models import Tenancy
        tenancy_id = request.query_params.get("tenancy")
        if not tenancy_id:
            return None, Response({"error": "tenancy is required."}, status=400)
        user = request.user
        try:
            if user.is_tenant:
                tenancy = Tenancy.objects.select_related(
                    'unit__property', 'tenant'
                ).get(id=tenancy_id, tenant=user)
            elif user.is_landlord:
                tenancy = Tenancy.objects.select_related(
                    'unit__property', 'tenant'
                ).get(id=tenancy_id, unit__property__owner=user)
            elif user.is_caretaker:
                tenancy = Tenancy.objects.select_related(
                    'unit__property', 'tenant'
                ).get(id=tenancy_id, unit__property__caretaker=user)
            else:
                return None, Response({"error": "Permission denied."}, status=403)
        except Tenancy.DoesNotExist:
            return None, Response({"error": "Tenancy not found."}, status=404)
        return tenancy, None

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
        except Exception:
            logger.exception("P&L PDF generation failed")
            return Response({"error": "PDF generation failed."}, status=500)

        import calendar
        month_label = date(year, month, 1).strftime('%Y-%m')
        key = f"reports/pnl/{prop.id}/{month_label}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception:
            logger.exception("MinIO upload failed for P&L report")
            return Response({"error": "File upload failed."}, status=500)

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
        except Exception:
            logger.exception("Aged receivables PDF generation failed")
            return Response({"error": "PDF generation failed."}, status=500)

        today = date.today().strftime('%Y-%m-%d')
        key = f"reports/aged/{prop.id}/{today}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception:
            logger.exception("MinIO upload failed for aged receivables report")
            return Response({"error": "File upload failed."}, status=500)

        return Response({
            "pdf_url": pdf_url,
            "generated_at": timezone.now().isoformat(),
            "summary": {"property": prop.name},
        })

    def _ledger(self, request):
        tenancy, err = self._get_tenancy(request)
        if err:
            return err

        date_from_str = request.query_params.get("date_from")
        date_to_str = request.query_params.get("date_to")
        try:
            date_from = date.fromisoformat(date_from_str) if date_from_str else date.today().replace(day=1)
            date_to = date.fromisoformat(date_to_str) if date_to_str else date.today()
        except ValueError:
            return Response({"error": "date_from and date_to must be ISO dates (YYYY-MM-DD)."}, status=400)
        if date_from > date_to:
            return Response({"error": "date_from cannot be after date_to."}, status=400)

        from .reports import generate_tenant_ledger
        try:
            pdf_bytes = generate_tenant_ledger(tenancy, date_from, date_to)
        except Exception:
            logger.exception("Tenant ledger PDF generation failed")
            return Response({"error": "PDF generation failed."}, status=500)

        key = f"reports/ledger/{tenancy.id}/{date_from}_{date_to}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception:
            logger.exception("MinIO upload failed for ledger report")
            return Response({"error": "File upload failed."}, status=500)

        return Response({
            "pdf_url": pdf_url,
            "generated_at": timezone.now().isoformat(),
            "summary": {
                "tenant": tenancy.tenant.get_full_name(),
                "unit": tenancy.unit.unit_number,
                "date_from": date_from.isoformat(),
                "date_to": date_to.isoformat(),
            },
        })

    def _statement(self, request):
        """Every month's bills for a building, by house. With download=xlsx or
        download=pdf, a link to the same as a file; with month=YYYY-MM, that
        month only."""
        if not request.user.is_landlord:
            return Response({"error": "Only the landlord can see the statement."}, status=403)
        prop, err = self._get_property(request)
        if err:
            return err

        from .statement import statement, statement_pdf, statement_xlsx

        data = statement(prop)
        months, deposits = data["months"], data["deposits"]
        only = request.query_params.get("month")
        if only:
            months = [m for m in months if m["month"] == only]

        kind = request.query_params.get("download")
        if kind not in ("xlsx", "pdf"):
            return Response({"property": prop.name, "months": _plain(months), "deposits": _plain(deposits)})

        build, content_type, disposition = {
            "xlsx": (statement_xlsx, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "attachment"),
            # Inline so the phone opens it to read rather than only saving it.
            "pdf": (statement_pdf, "application/pdf", "inline"),
        }[kind]
        try:
            content = build(prop, months, deposits)
        except Exception:
            logger.exception("Statement %s generation failed", kind)
            return Response({"error": "The file could not be made."}, status=500)
        name = f"{prop.name} statement {only or 'all months'}.{kind}"
        key = f"reports/statement/{prop.id}/{timezone.now():%Y%m%d%H%M%S}.{kind}"
        try:
            stored = upload_private_file(
                key, content, content_type, content_disposition=f'{disposition}; filename="{name}"',
            )
            url = private_file_url(stored)
        except Exception:
            logger.exception("MinIO upload failed for statement")
            return Response({"error": "File upload failed."}, status=500)
        return Response({"file_url": url, "generated_at": timezone.now().isoformat()})

    def _rent_roll(self, request):
        prop, err = self._get_property(request)
        if err:
            return err

        from .reports import generate_rent_roll
        try:
            pdf_bytes = generate_rent_roll(prop)
        except Exception:
            logger.exception("Rent roll PDF generation failed")
            return Response({"error": "PDF generation failed."}, status=500)

        today = date.today().strftime('%Y-%m-%d')
        key = f"reports/rent_roll/{prop.id}/{today}.pdf"
        try:
            pdf_url = _upload_pdf(pdf_bytes, key)
        except Exception:
            logger.exception("MinIO upload failed for rent roll report")
            return Response({"error": "File upload failed."}, status=500)

        return Response({
            "pdf_url": pdf_url,
            "generated_at": timezone.now().isoformat(),
            "summary": {"property": prop.name},
        })
