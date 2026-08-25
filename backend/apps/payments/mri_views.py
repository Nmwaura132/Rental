from datetime import date, timedelta

from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import User
from apps.payments.mri import mri_summary


class MRIStatementView(APIView):
    """Monthly Rental Income figures for the requesting landlord.

    GET /api/v1/payments/mri/?year=2026&month=9
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Only an owner has an MRI liability; a caretaker or tenant asking for
        # one would otherwise get a confusing empty statement instead of a clear
        # refusal.
        if request.user.role != User.Role.LANDLORD:
            return Response(
                {"error": "Only landlords have a rental income tax statement."},
                status=status.HTTP_403_FORBIDDEN,
            )

        today = date.today()
        try:
            year = int(request.query_params.get("year", today.year))
            month = int(request.query_params.get("month", today.month))
        except (TypeError, ValueError):
            return Response(
                {"error": "year and month must be whole numbers."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not 1 <= month <= 12:
            return Response(
                {"error": "month must be between 1 and 12."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # WHY bound the year: date() raises for year 0 or 10000, and an
        # uncaught ValueError here is a 500 — which on a DEBUG staging host
        # renders the Django error page, settings and all.
        if not 2000 <= year <= 2100:
            return Response(
                {"error": "year must be between 2000 and 2100."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        period_start = date(year, month, 1)
        period_end = (
            date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
        ) - timedelta(days=1)

        summary = mri_summary(
            owner=request.user,
            period_start=period_start,
            period_end=period_end,
        )
        # MRI for a month is due by the 20th of the month after it.
        due = date(year + 1, 1, 20) if month == 12 else date(year, month + 1, 20)
        summary["filing_due_date"] = due
        return Response(summary)
