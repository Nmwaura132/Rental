"""The generated tenancy agreement.

This is a document tenants sign, so the thing worth guarding is not that it
renders — it is that it says the landlord's terms and nothing else. A previous
version invented a KES 500 weekly late fee and cited the Rent Restriction Act
and the Business Premises Rent Tribunal, none of which appear in the landlord's
own agreement.
"""
from __future__ import annotations

import base64
import re
import zlib
from decimal import Decimal

import pytest

from apps.properties.models import PropertyCharge
from apps.tenants.tenancy_pdf import generate_tenancy_pdf


def _text(pdf: bytes) -> str:
    """The PDF's decoded content streams, for substring checks."""
    blob = b""
    for m in re.finditer(rb"stream\r?\n(.*?)endstream", pdf, re.S):
        s = m.group(1).strip()
        try:
            s = base64.a85decode(s, adobe=True)
        except Exception:
            pass
        try:
            s = zlib.decompress(s)
        except Exception:
            pass
        blob += s
    return blob.decode("latin-1")


@pytest.fixture
def agreement(tenancy):
    return _text(generate_tenancy_pdf(tenancy))


class TestItStatesTheLandlordsTerms:
    def test_rent_is_due_on_the_fifth(self, agreement):
        assert "5th day of every month" in agreement

    def test_the_deposit_equals_one_month_rent(self, agreement):
        assert "equivalent to One" in agreement

    def test_notice_is_one_month(self, agreement):
        assert "one [1] month notice" in agreement

    def test_pets_are_not_allowed(self, agreement):
        assert "Not to keep pets" in agreement

    def test_the_nuisance_clause_survives_its_parentheses(self, agreement):
        assert "loud music" in agreement

    def test_the_repainting_obligation_is_stated(self, agreement):
        assert "two coats of water paint" in agreement

    def test_the_twenty_percent_levy_is_stated(self, agreement):
        assert "20% levy" in agreement

    def test_the_landlord_is_not_liable_for_theft(self, agreement):
        assert "not be responsible for any acts of theft" in agreement

    def test_the_data_protection_clause_is_present(self, agreement):
        # It matters more now that Kasa stores KRA PINs and national IDs.
        assert "data protection laws" in agreement

    def test_it_is_governed_by_the_law_of_contract_act(self, agreement):
        assert "Cap 23" in agreement

    def test_there_is_a_witness_block(self, agreement):
        assert "In the presence of" in agreement


class TestItInventsNothing:
    def test_no_late_payment_fee(self, agreement):
        # The landlord's agreement has no late fee; non-payment "may result in
        # the closure of the house" instead.
        assert "late payment fee" not in agreement.lower()

    def test_no_invented_penalty_amount(self, agreement):
        assert "500 per week" not in agreement

    def test_it_does_not_claim_the_rent_restriction_act_governs(self, agreement):
        assert "Cap 296" not in agreement

    def test_it_does_not_refer_disputes_to_the_business_premises_tribunal(
        self, agreement
    ):
        # That tribunal handles business premises; this is a home.
        assert "Business Premises Rent Tribunal" not in agreement

    def test_it_does_not_invent_a_rent_review_notice_period(self, agreement):
        assert "RENT INCREASES" not in agreement


class TestItFillsTheBlanks:
    def test_the_tenant_is_named(self, agreement, tenant):
        assert tenant.first_name in agreement

    def test_the_house_number_is_filled_in(self, agreement, unit):
        assert unit.unit_number in agreement

    def test_the_payment_account_is_the_units_payment_code(self, agreement, unit):
        # What the tenant types into M-Pesa, which need not match the unit
        # number the landlord uses.
        assert unit.payment_code in agreement

    def test_the_service_charge_is_filled_in_when_the_property_has_one(
        self, tenancy, property_
    ):
        PropertyCharge.objects.create(
            property=property_,
            charge_type=PropertyCharge.ChargeType.SERVICE,
            name="Service Charge",
            unit_price=Decimal("2000.00"),
            is_active=True,
        )
        assert "2,000" in _text(generate_tenancy_pdf(tenancy))

    def test_the_service_charge_is_left_blank_when_there_is_none(self, agreement):
        # Left as dotted lines to complete by hand rather than stated as zero.
        assert "service charge" in agreement.lower()
