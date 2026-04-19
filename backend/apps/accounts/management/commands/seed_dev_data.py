"""
Management command: seed the database with dev users and sample data.

Creates:
  • Landlord  — +254100368483 / DevLandlord@2026
  • Tenant     — +254722870015 / DevTenant@2026  (Nelson Mwaura)
  • Property   — Whitty Apartments (Nairobi)
  • 4 Units    — 101, 102, 201, 202
  • Lease      — Nelson in Unit 201, active Jan–Dec 2026
  • Invoices   — Feb 2026 (paid), Mar 2026 (paid), Apr 2026 (overdue)

Safe to re-run — uses get_or_create throughout.

Usage:
    docker compose exec api python manage.py seed_dev_data
"""
import uuid
from datetime import date
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.conf import settings

User = get_user_model()


class Command(BaseCommand):
    help = "Seed dev users, a sample property, lease, and invoices."

    def handle(self, *args, **options):
        from apps.properties.models import Property, Unit
        from apps.tenants.models import Lease
        from apps.payments.models import Invoice, Payment

        # ── Users ─────────────────────────────────────────────────────────────
        landlord, created = User.objects.get_or_create(
            phone_number="+254100368483",
            defaults={
                "first_name": "Dev",
                "last_name": "Landlord",
                "role": User.Role.LANDLORD,
                "is_active": True,
                "is_staff": True,
            },
        )
        if created:
            landlord.set_password("DevLandlord@2026")
            landlord.save(update_fields=["password"])
            self.stdout.write(self.style.SUCCESS("  Created landlord +254100368483"))
        else:
            self.stdout.write("  Landlord already exists — skipping")

        tenant, created = User.objects.get_or_create(
            phone_number="+254722870015",
            defaults={
                "first_name": "Nelson",
                "last_name": "Mwaura",
                "role": User.Role.TENANT,
                "is_active": True,
            },
        )
        if created:
            tenant.set_password("DevTenant@2026")
            tenant.save(update_fields=["password"])
            self.stdout.write(self.style.SUCCESS("  Created tenant +254722870015 (Nelson Mwaura)"))
        else:
            self.stdout.write("  Tenant already exists — skipping")

        # ── Property ──────────────────────────────────────────────────────────
        prop, created = Property.objects.get_or_create(
            owner=landlord,
            name="Whitty Apartments",
            defaults={
                "address": "Whitfield Road, Westlands",
                "county": "Nairobi",
                "town": "Westlands",
            },
        )
        if created:
            self.stdout.write(self.style.SUCCESS("  Created property: Whitty Apartments"))
        else:
            self.stdout.write("  Property already exists — skipping")

        # ── Units ─────────────────────────────────────────────────────────────
        # Unit.save() appends a random suffix on creation for M-Pesa uniqueness.
        # We check existence by (property, unit_number startswith) to stay idempotent.
        def get_or_create_unit(number, unit_type, rent, deposit, floor=0):
            existing = Unit.objects.filter(
                property=prop, unit_number__startswith=f"{number}-"
            ).first()
            if existing:
                return existing, False
            unit = Unit(
                property=prop,
                unit_number=number,   # save() will append "-XXXX"
                unit_type=unit_type,
                rent_amount=Decimal(str(rent)),
                deposit_amount=Decimal(str(deposit)),
                floor=floor,
            )
            unit.save()
            return unit, True

        unit101, c = get_or_create_unit("101", Unit.UnitType.ONE_BED,   25000, 50000, floor=1)
        if c: self.stdout.write(self.style.SUCCESS(f"  Created unit {unit101.unit_number}"))

        unit102, c = get_or_create_unit("102", Unit.UnitType.BEDSITTER, 15000, 30000, floor=1)
        if c: self.stdout.write(self.style.SUCCESS(f"  Created unit {unit102.unit_number}"))

        unit201, c = get_or_create_unit("201", Unit.UnitType.ONE_BED,   28000, 56000, floor=2)
        if c: self.stdout.write(self.style.SUCCESS(f"  Created unit {unit201.unit_number}"))

        unit202, c = get_or_create_unit("202", Unit.UnitType.TWO_BED,   35000, 70000, floor=2)
        if c: self.stdout.write(self.style.SUCCESS(f"  Created unit {unit202.unit_number}"))

        # ── Lease ─────────────────────────────────────────────────────────────
        lease, created = Lease.objects.get_or_create(
            tenant=tenant,
            unit=unit201,
            defaults={
                "start_date": date(2026, 1, 1),
                "end_date": date(2026, 12, 31),
                "rent_amount": Decimal("28000"),
                "deposit_amount": Decimal("56000"),
                "deposit_paid": True,
                "status": Lease.Status.ACTIVE,
            },
        )
        if created:
            # Mark unit as occupied
            unit201.status = Unit.Status.OCCUPIED
            unit201.save(update_fields=["status"])
            self.stdout.write(self.style.SUCCESS(
                f"  Created lease: Nelson → {unit201.unit_number}"
            ))
        else:
            self.stdout.write("  Lease already exists — skipping")

        # ── Invoices ──────────────────────────────────────────────────────────
        def make_invoice(number, period_start, period_end, due_date, inv_status,
                         amount_paid=Decimal("0")):
            inv, created = Invoice.objects.get_or_create(
                invoice_number=number,
                defaults={
                    "lease": lease,
                    "amount_due": Decimal("28000"),
                    "amount_paid": amount_paid,
                    "due_date": due_date,
                    "period_start": period_start,
                    "period_end": period_end,
                    "status": inv_status,
                },
            )
            return inv, created

        # February 2026 — paid
        inv_feb, c = make_invoice(
            "INV-202602-001",
            date(2026, 2, 1), date(2026, 2, 28), date(2026, 2, 5),
            Invoice.Status.PAID, amount_paid=Decimal("28000"),
        )
        if c:
            Payment.objects.create(
                invoice=inv_feb,
                method=Payment.Method.MPESA,
                status=Payment.Status.CONFIRMED,
                amount=Decimal("28000"),
                mpesa_receipt_number="PB12345678",
                mpesa_phone="+254722870015",
                mpesa_account_ref=unit201.unit_number,
                idempotency_key=f"seed:feb2026:{uuid.uuid4().hex[:8]}",
                paid_at=date(2026, 2, 6),
            )
            self.stdout.write(self.style.SUCCESS("  Created Feb 2026 invoice (PAID)"))

        # March 2026 — paid
        inv_mar, c = make_invoice(
            "INV-202603-001",
            date(2026, 3, 1), date(2026, 3, 31), date(2026, 3, 5),
            Invoice.Status.PAID, amount_paid=Decimal("28000"),
        )
        if c:
            Payment.objects.create(
                invoice=inv_mar,
                method=Payment.Method.MPESA,
                status=Payment.Status.CONFIRMED,
                amount=Decimal("28000"),
                mpesa_receipt_number="PB23456789",
                mpesa_phone="+254722870015",
                mpesa_account_ref=unit201.unit_number,
                idempotency_key=f"seed:mar2026:{uuid.uuid4().hex[:8]}",
                paid_at=date(2026, 3, 6),
            )
            self.stdout.write(self.style.SUCCESS("  Created Mar 2026 invoice (PAID)"))

        # April 2026 — overdue (due 5 Apr, today is after that)
        inv_apr, c = make_invoice(
            "INV-202604-001",
            date(2026, 4, 1), date(2026, 4, 30), date(2026, 4, 5),
            Invoice.Status.OVERDUE,
        )
        if c:
            self.stdout.write(self.style.SUCCESS("  Created Apr 2026 invoice (OVERDUE)"))

        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("Dev data seeded successfully."))
        self.stdout.write("")
        self.stdout.write(f"  Landlord : +254100368483 / DevLandlord@2026")
        self.stdout.write(f"  Tenant   : +254722870015 / DevTenant@2026 (Nelson Mwaura)")
        self.stdout.write(f"  Property : Whitty Apartments")
        self.stdout.write(f"  Unit     : {unit201.unit_number} (Nelson's unit)")
        self.stdout.write("")
        self.stdout.write("  Update dev_picker_screen.dart sublabel to match the unit number above if needed.")
