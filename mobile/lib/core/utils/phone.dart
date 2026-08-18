/// Kenyan phone number handling for UI fields.
///
/// Fields show a fixed "+254" prefix so users only type the 9-digit local
/// number (e.g. 712345678), the way they'd read it off their own SIM. These
/// helpers tolerate whatever actually lands in the box — a leading 0 out of
/// habit, a pasted +254/254 prefix, or just the bare 9 digits — because the
/// backend's normalizer (apps.core.utils.phone.normalize_phone) is the
/// actual source of truth; these just need to produce something it accepts.
library;

/// Converts phone input into E.164 (+254...) for API calls.
String normalizeKenyanPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('254')) return '+$digits';
  if (digits.startsWith('0')) return '+254${digits.substring(1)}';
  return '+254$digits';
}

/// Strips any 254/0 prefix, leaving just the local digits a field displays
/// next to its fixed "+254" prefix decoration.
String toLocalKenyanDigits(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('254') && digits.length > 9) {
    return digits.substring(3);
  }
  if (digits.startsWith('0') && digits.length == 10) {
    return digits.substring(1);
  }
  return digits;
}

/// Validator for a phone field showing a fixed "+254" prefix.
String? validateKenyanPhone(String? value) {
  final local = toLocalKenyanDigits(value ?? '');
  if (local.isEmpty) return 'Phone number is required';
  if (local.length != 9) return 'Enter a valid phone number';
  return null;
}
