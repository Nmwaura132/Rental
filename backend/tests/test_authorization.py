from datetime import date
from decimal import Decimal

from rest_framework.test import APIClient

from django.contrib.auth import get_user_model
from django.utils import timezone

from apps.properties.models import Property, Unit
from apps.payments.models import Payment
from apps.tenants.models import Tenancy


def _registration_payload(phone_number):
    return {
        "phone_number": phone_number,
        "first_name": "New",
        "last_name": "Tenant",
        "role": "tenant",
        "password": "NewTenant@Test1",
        "password_confirm": "NewTenant@Test1",
    }


def test_anonymous_user_cannot_register_an_account(db):
    response = APIClient().post(
        "/api/v1/auth/register/",
        _registration_payload("+254700333001"),
        format="json",
    )

    assert response.status_code == 401


def test_tenant_cannot_register_another_account(db, tenant):
    client = APIClient()
    client.force_authenticate(user=tenant)

    response = client.post(
        "/api/v1/auth/register/",
        _registration_payload("+254700333002"),
        format="json",
    )

    assert response.status_code == 403


def test_landlord_registered_tenant_is_owned_by_landlord(db, landlord):
    client = APIClient()
    client.force_authenticate(user=landlord)

    response = client.post(
        "/api/v1/auth/register/",
        _registration_payload("+254700333003"),
        format="json",
    )

    assert response.status_code == 201
    created = get_user_model().objects.get(phone_number="+254700333003")
    assert created.created_by == landlord


def test_password_change_revokes_existing_access_token(db, landlord):
    client = APIClient()
    login = client.post(
        "/api/v1/auth/login/",
        {
            "phone_number": landlord.phone_number,
            "password": "Landlord@Test1",
        },
        format="json",
    )
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

    changed = client.post(
        "/api/v1/auth/change-password/",
        {
            "old_password": "Landlord@Test1",
            "new_password": "RotatedLandlord@Test2",
        },
        format="json",
    )
    stale_token_response = client.get("/api/v1/auth/profile/")

    assert changed.status_code == 200
    assert stale_token_response.status_code == 401


def test_tenant_cannot_delete_their_tenanted_property(
    db, tenant, property_, tenancy
):
    client = APIClient()
    client.force_authenticate(user=tenant)

    response = client.delete(f"/api/v1/properties/{property_.id}/")

    assert response.status_code == 403
    assert Property.objects.filter(id=property_.id).exists()


def test_landlord_cannot_delete_property_with_tenancy_history(
    db, landlord, property_, tenancy
):
    client = APIClient()
    client.force_authenticate(user=landlord)

    response = client.delete(f"/api/v1/properties/{property_.id}/")

    assert response.status_code == 409
    assert Property.objects.filter(id=property_.id).exists()
    assert Tenancy.objects.filter(id=tenancy.id).exists()


def test_tenant_cannot_rename_their_tenanted_property(
    db, tenant, property_, tenancy
):
    client = APIClient()
    client.force_authenticate(user=tenant)

    response = client.patch(
        f"/api/v1/properties/{property_.id}/",
        {"name": "Taken over"},
        format="json",
    )

    assert response.status_code == 403
    property_.refresh_from_db()
    assert property_.name == "Kasa Test Apartments"


def test_tenant_cannot_add_a_unit_to_their_tenanted_property(
    db, tenant, property_, tenancy
):
    client = APIClient()
    client.force_authenticate(user=tenant)

    response = client.post(
        "/api/v1/properties/units/",
        {
            "property": property_.id,
            "unit_number": "ILLEGAL",
            "unit_type": "1bed",
            "rent_amount": "1.00",
            "deposit_amount": "1.00",
            "floor": 0,
        },
        format="json",
    )

    assert response.status_code == 403


def test_landlord_cannot_add_a_unit_to_another_landlords_property(
    db, landlord
):
    other_landlord = get_user_model().objects.create_user(
        phone_number="+254700222000",
        password="OtherLandlord@Test1",
        first_name="Other",
        last_name="Landlord",
        role="landlord",
    )
    other_property = Property.objects.create(
        owner=other_landlord,
        name="Other Apartments",
    )
    client = APIClient()
    client.force_authenticate(user=landlord)

    response = client.post(
        "/api/v1/properties/units/",
        {
            "property": other_property.id,
            "unit_number": "A1",
            "unit_type": "1bed",
            "rent_amount": "10000.00",
            "deposit_amount": "10000.00",
            "floor": 0,
        },
        format="json",
    )

    assert response.status_code == 403


def test_landlord_cannot_create_an_invoice_for_another_landlords_tenancy(
    db, landlord
):
    other_landlord = get_user_model().objects.create_user(
        phone_number="+254700222001",
        password="OtherLandlord@Test1",
        first_name="Other",
        last_name="Landlord",
        role="landlord",
    )
    other_tenant = get_user_model().objects.create_user(
        phone_number="+254700222002",
        password="OtherTenant@Test1",
        first_name="Other",
        last_name="Tenant",
        role="tenant",
    )
    other_property = Property.objects.create(
        owner=other_landlord,
        name="Other Apartments",
    )
    other_unit = Unit.objects.create(
        property=other_property,
        unit_number="A1",
        unit_type="1bed",
        rent_amount=Decimal("10000.00"),
        deposit_amount=Decimal("10000.00"),
    )
    other_tenancy = Tenancy.objects.create(
        tenant=other_tenant,
        unit=other_unit,
        start_date=date.today(),
        rent_amount=Decimal("10000.00"),
        deposit_amount=Decimal("10000.00"),
    )
    client = APIClient()
    client.force_authenticate(user=landlord)

    response = client.post(
        "/api/v1/payments/invoices/",
        {
            "tenancy": other_tenancy.id,
            "amount_due": "10000.00",
            "due_date": date.today().isoformat(),
            "period_start": date.today().isoformat(),
            "period_end": date.today().isoformat(),
        },
        format="json",
    )

    assert response.status_code == 403


def test_landlord_cannot_create_a_tenancy_for_another_landlords_unit(
    db, landlord, tenant
):
    other_landlord = get_user_model().objects.create_user(
        phone_number="+254700222003",
        password="OtherLandlord@Test1",
        first_name="Other",
        last_name="Landlord",
        role="landlord",
    )
    other_property = Property.objects.create(
        owner=other_landlord,
        name="Other Apartments",
    )
    other_unit = Unit.objects.create(
        property=other_property,
        unit_number="A1",
        unit_type="1bed",
        rent_amount=Decimal("10000.00"),
        deposit_amount=Decimal("10000.00"),
    )
    client = APIClient()
    client.force_authenticate(user=landlord)

    response = client.post(
        "/api/v1/tenants/tenancies/",
        {
            "tenant": tenant.id,
            "unit": other_unit.id,
            "start_date": date.today().isoformat(),
            "rent_amount": "10000.00",
            "deposit_amount": "10000.00",
        },
        format="json",
    )

    assert response.status_code == 403


def test_tenant_cannot_change_their_invoice_amount(db, tenant, invoice):
    client = APIClient()
    client.force_authenticate(user=tenant)

    response = client.patch(
        f"/api/v1/payments/invoices/{invoice.id}/",
        {"amount_due": "1.00"},
        format="json",
    )

    assert response.status_code == 403
    invoice.refresh_from_db()
    assert invoice.amount_due != 1


def test_tenant_cannot_terminate_their_own_tenancy(db, tenant, tenancy):
    client = APIClient()
    client.force_authenticate(user=tenant)

    response = client.patch(
        f"/api/v1/tenants/tenancies/{tenancy.id}/",
        {"status": "terminated"},
        format="json",
    )

    assert response.status_code == 403
    tenancy.refresh_from_db()
    assert tenancy.status == "active"


def test_caretaker_can_view_but_cannot_record_payments(
    db, caretaker, property_, invoice
):
    property_.caretaker = caretaker
    property_.save(update_fields=["caretaker"])
    client = APIClient()
    client.force_authenticate(user=caretaker)

    listed = client.get("/api/v1/payments/invoices/")
    recorded = client.post(
        "/api/v1/payments/record/",
        {
            "invoice": invoice.id,
            "method": "cash",
            "amount": "1000.00",
        },
        format="json",
    )

    assert listed.status_code == 200
    assert recorded.status_code == 403


def test_paid_invoice_financial_fields_cannot_be_edited(db, landlord, invoice):
    Payment.objects.create(
        invoice=invoice,
        method=Payment.Method.CASH,
        status=Payment.Status.CONFIRMED,
        amount=Decimal("1000.00"),
        idempotency_key="manual:invoice-lock",
        paid_at=timezone.now(),
    )
    client = APIClient()
    client.force_authenticate(user=landlord)

    response = client.patch(
        f"/api/v1/payments/invoices/{invoice.id}/",
        {"amount_due": "1.00"},
        format="json",
    )

    assert response.status_code == 400
