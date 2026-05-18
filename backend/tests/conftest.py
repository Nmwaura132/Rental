"""Shared pytest fixtures for Kasa.

These fixtures cover the minimum graph needed to exercise money + auth paths:
landlord -> property -> unit -> lease -> tenant -> invoice. Build helpers stay
small; tests that need more should create their own factories.
"""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from django.contrib.auth import get_user_model

User = get_user_model()


@pytest.fixture
def landlord(db):
    return User.objects.create_user(
        phone_number="+254700111000",
        password="Landlord@Test1",
        first_name="Test",
        last_name="Landlord",
        role=User.Role.LANDLORD,
    )


@pytest.fixture
def tenant(db):
    return User.objects.create_user(
        phone_number="+254700111111",
        password="Tenant@Test1",
        first_name="Test",
        last_name="Tenant",
        role=User.Role.TENANT,
    )


@pytest.fixture
def property_(db, landlord):
    from apps.properties.models import Property
    return Property.objects.create(owner=landlord, name="Kasa Test Apartments")


@pytest.fixture
def unit(db, property_):
    from apps.properties.models import Unit
    return Unit.objects.create(
        property=property_,
        unit_number="A1",
        unit_type=Unit.UnitType.ONE_BED,
        rent_amount=Decimal("15000.00"),
        deposit_amount=Decimal("30000.00"),
    )


@pytest.fixture
def lease(db, tenant, unit):
    from apps.tenants.models import Lease
    return Lease.objects.create(
        tenant=tenant,
        unit=unit,
        start_date=date.today() - timedelta(days=30),
        rent_amount=unit.rent_amount,
        deposit_amount=unit.deposit_amount,
    )


@pytest.fixture
def invoice(db, lease):
    from apps.payments.models import Invoice
    period_start = date.today().replace(day=1)
    return Invoice.objects.create(
        lease=lease,
        invoice_number="INV-TEST-000001",
        amount_due=lease.rent_amount,
        amount_paid=Decimal("0"),
        due_date=period_start + timedelta(days=7),
        period_start=period_start,
        period_end=period_start + timedelta(days=30),
    )
