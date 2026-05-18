"""Phone normalization round-trips. The whole codebase assumes E.164; the
moment normalize_phone returns something else, M-Pesa matching breaks."""
import pytest

from apps.core.utils.phone import normalize_phone
from django.core.exceptions import ValidationError


def test_normalizes_local_kenyan_zero_prefix():
    assert normalize_phone("0712345678") == "+254712345678"


def test_normalizes_country_code_without_plus():
    assert normalize_phone("254712345678") == "+254712345678"


def test_normalizes_full_e164():
    assert normalize_phone("+254712345678") == "+254712345678"


def test_strips_whitespace_and_dashes():
    assert normalize_phone("+254 712 345-678") == "+254712345678"


def test_empty_returns_empty():
    assert normalize_phone("") == ""


def test_rejects_invalid_number():
    with pytest.raises(ValidationError):
        normalize_phone("12345")
