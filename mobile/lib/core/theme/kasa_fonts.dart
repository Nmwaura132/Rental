import 'package:flutter/widgets.dart';

/// Geist (text) and Geist Mono (codes, references), bundled in assets/fonts.
///
/// WHY bundled rather than google_fonts: the package has no Geist, and a
/// bundled font also renders on first launch with no network.
///
/// Only weights 400, 500 and 600 are shipped; anything heavier snaps to 600,
/// which is the heaviest weight the design uses.
class KasaFont {
  KasaFont._();

  static const sansFamily = 'Geist';
  static const monoFamily = 'Geist Mono';

  static TextStyle sans({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    List<FontFeature>? fontFeatures,
  }) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        fontStyle: fontStyle,
        decoration: decoration,
        fontFeatures: fontFeatures,
      );

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    List<FontFeature>? fontFeatures,
  }) =>
      TextStyle(
        fontFamily: monoFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        fontStyle: fontStyle,
        decoration: decoration,
        fontFeatures: fontFeatures,
      );
}
