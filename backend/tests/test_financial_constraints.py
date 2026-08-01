from decimal import Decimal

import pytest
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.payments.models import Payment


@pytest.mark.django_db
def test_database_rejects_non_positive_payment(invoice):
    with pytest.raises(IntegrityError), transaction.atomic():
        Payment.objects.create(
            invoice=invoice,
            method=Payment.Method.CASH,
            status=Payment.Status.CONFIRMED,
            amount=Decimal("0.00"),
            idempotency_key="manual:non-positive",
            paid_at=timezone.now(),
        )
