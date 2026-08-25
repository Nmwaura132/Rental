"""KRA PIN normalization and validation.

A wrong PIN is not cosmetic: eRITS files the landlord's monthly return against
it, so a typo files their rent under someone else's name.
"""
from __future__ import annotations

import pytest
from django.core.exceptions import ValidationError

from apps.core.utils.kra import normalize_kra_pin, validate_kra_pin


class TestValidateKraPin:
    def test_accepts_a_personal_pin(self):
        assert validate_kra_pin("A012345678Z") is None

    def test_accepts_a_company_pin(self):
        assert validate_kra_pin("P012345678Z") is None

    def test_accepts_lowercase_input(self):
        assert validate_kra_pin("a012345678z") is None

    def test_accepts_a_pin_padded_with_spaces(self):
        assert validate_kra_pin("  A012345678Z  ") is None

    def test_blank_is_allowed(self):
        # A PIN is needed to file, not to record a tenant. Refusing the record
        # outright would push landlords to invent one.
        assert validate_kra_pin("") is None

    def test_none_is_allowed(self):
        assert validate_kra_pin(None) is None

    def test_rejects_a_prefix_that_is_not_a_or_p(self):
        with pytest.raises(ValidationError):
            validate_kra_pin("B012345678Z")

    def test_rejects_too_few_digits(self):
        with pytest.raises(ValidationError):
            validate_kra_pin("A01234567Z")

    def test_rejects_too_many_digits(self):
        with pytest.raises(ValidationError):
            validate_kra_pin("A0123456789Z")

    def test_rejects_a_missing_check_letter(self):
        with pytest.raises(ValidationError):
            validate_kra_pin("A0123456789")

    def test_rejects_a_digit_where_the_check_letter_belongs(self):
        with pytest.raises(ValidationError):
            validate_kra_pin("A0123456781")

    def test_rejects_letters_in_the_numeric_block(self):
        with pytest.raises(ValidationError):
            validate_kra_pin("AO12345678Z")

    def test_rejects_a_national_id_pasted_into_the_pin_field(self):
        with pytest.raises(ValidationError):
            validate_kra_pin("12345678")

    def test_error_names_the_expected_shape(self):
        with pytest.raises(ValidationError) as exc:
            validate_kra_pin("nonsense")
        assert exc.value.code == "invalid_kra_pin"


class TestNormalizeKraPin:
    def test_upper_cases_a_pin(self):
        assert normalize_kra_pin("a012345678z") == "A012345678Z"

    def test_strips_surrounding_whitespace(self):
        assert normalize_kra_pin("  A012345678Z ") == "A012345678Z"

    def test_removes_internal_spaces(self):
        assert normalize_kra_pin("A 012345678 Z") == "A012345678Z"

    def test_blank_becomes_none(self):
        # Storing "" and None for the same absence would make "has a PIN"
        # queries depend on which code path wrote the row.
        assert normalize_kra_pin("   ") is None

    def test_none_stays_none(self):
        assert normalize_kra_pin(None) is None
