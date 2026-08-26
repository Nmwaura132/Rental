import 'package:flutter/services.dart';

/// A KRA PIN is a letter, nine digits, then a check letter — "A012345678Z".
/// Personal PINs start with A and non-individual ones with P, since a landlord
/// may hold property through a company.
///
/// [0-9] rather than \d, matching the backend: \d would accept Arabic-Indic and
/// Devanagari digits, which reach eRITS as garbage.
final _kraPinPattern = RegExp(r'^[AP][0-9]{9}[A-Z]$');

String? normalizeKraPin(String? value) {
  if (value == null) return null;
  final cleaned = value.replaceAll(' ', '').toUpperCase().trim();
  return cleaned.isEmpty ? null : cleaned;
}

/// Blank passes: a PIN is needed to file, not to record a tenant. Refusing the
/// whole tenant over a missing PIN would just push landlords to invent one.
String? validateKraPin(String? value) {
  final pin = normalizeKraPin(value);
  if (pin == null) return null;
  if (!_kraPinPattern.hasMatch(pin)) {
    return 'Enter a valid KRA PIN, e.g. A012345678Z';
  }
  return null;
}

/// Upper-cases as the user types, so the field shows the PIN in the shape KRA
/// prints it rather than correcting it silently on save.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
