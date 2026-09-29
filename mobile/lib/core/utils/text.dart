/// Display text from a machine value: `in_progress` -> `In progress`,
/// `PARTIALLY_PAID` -> `Partially paid`.
///
/// WHY one helper: status and channel strings arrive from the API in whatever
/// case the backend uses. The old UI hid that by upper-casing everything; with
/// sentence case, every screen needs the same conversion, so it lives here
/// instead of being re-derived per screen.
String sentenceCase(String raw) {
  final s = raw.replaceAll('_', ' ').trim();
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}
