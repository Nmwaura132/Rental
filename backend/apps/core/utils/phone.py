import phonenumbers
from django.core.exceptions import ValidationError

def normalize_phone(phone_str, region="KE"):
    """
    Standardize any phone number format into E.164 (e.g. +254712345678).
    Supports: 0712345678, 254712345678, +254712345678.
    """
    if not phone_str:
        return ""
    
    # Strip whitespace and common separators
    clean_str = "".join(c for c in str(phone_str) if c.isdigit() or c == "+")
    
    try:
        # Parse the number
        parsed = phonenumbers.parse(clean_str, region)
        
        # Validate that it's a possible number for the region
        if not phonenumbers.is_valid_number(parsed):
            raise ValidationError(f"'{phone_str}' is not a valid {region} phone number.")
            
        # Standardize to E.164 (+254...)
        return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
        
    except phonenumbers.phonenumberutil.NumberParseException:
        raise ValidationError(f"Could not parse phone number '{phone_str}'.")

def validate_phone(value):
    """Django validator for model fields."""
    normalize_phone(value)
