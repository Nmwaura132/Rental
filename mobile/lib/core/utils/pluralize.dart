/// Returns [singular] when [count] is 1, [plural] otherwise.
///
/// Kasa's counts (properties, units) are almost always small and frequently
/// hit exactly 1 — a new landlord's first property, a studio's one unit — so
/// "1 PROPERTIES" is a real, common sighting, not an edge case.
String pluralize(num count, String singular, String plural) =>
    count == 1 ? singular : plural;
