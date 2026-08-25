"""KRA identifier handling for eRITS rental income reporting.

KRA's Electronic Rental Income Tax System links each registered property to the
PIN of the tenant occupying it, so a wrong PIN is not a cosmetic error — it
misfiles the landlord's monthly return against a stranger.
"""

import re

from django.core.exceptions import ValidationError

# A KRA PIN is a letter, nine digits, then a check letter — "A000000000A".
# Personal PINs start with A and non-individual ones with P; both are accepted
# because a landlord may hold property through a company.
# [0-9] not \d: \d is Unicode-aware in Python, so Arabic-Indic and
# Devanagari digits would pass and reach eRITS as garbage.
_KRA_PIN_RE = re.compile(r"^[AP][0-9]{9}[A-Z]$")


def normalize_kra_pin(value: str | None) -> str | None:
    """Upper-case and strip a PIN, returning None for anything blank.

    Kept separate from validation so callers can normalize input before storing
    without deciding what to do about a bad value.
    """
    if value is None:
        return None
    cleaned = value.strip().replace(" ", "").upper()
    return cleaned or None


def validate_kra_pin(value: str | None) -> None:
    """Raise ValidationError unless `value` looks like a KRA PIN.

    Blank passes: a PIN is required to file, but not to create a tenant record —
    refusing the record outright would just push landlords to type a fake one.
    """
    if not value:
        return
    if not _KRA_PIN_RE.match(normalize_kra_pin(value) or ""):
        raise ValidationError(
            "Enter a valid KRA PIN — a letter, nine digits, then a letter (e.g. A012345678Z).",
            code="invalid_kra_pin",
        )
