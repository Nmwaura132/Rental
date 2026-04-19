import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/kasa_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final cs = ColorScheme(
      brightness: brightness,

      // Primary — salmon
      primary:          isDark ? KasaColors.darkPrimary      : KasaColors.lightPrimary,
      onPrimary:        isDark ? KasaColors.darkPrimaryInk   : KasaColors.lightPrimaryInk,
      primaryContainer: isDark ? KasaColors.darkPrimary.withValues(alpha: 0.2)
                               : KasaColors.lightPrimary.withValues(alpha: 0.15),
      onPrimaryContainer: isDark ? KasaColors.darkPrimary    : KasaColors.lightPrimary,

      // Secondary — periwinkle
      secondary:          isDark ? KasaColors.darkSecondary      : KasaColors.lightSecondary,
      onSecondary:        isDark ? KasaColors.darkSecondaryInk   : KasaColors.lightSecondaryInk,
      secondaryContainer: isDark ? KasaColors.darkSecondary.withValues(alpha: 0.2)
                                 : KasaColors.lightSecondary.withValues(alpha: 0.15),
      onSecondaryContainer: isDark ? KasaColors.darkSecondary    : KasaColors.lightSecondary,

      // Tertiary — yellow/amber
      tertiary:          isDark ? KasaColors.darkTertiary      : KasaColors.lightTertiary,
      onTertiary:        isDark ? KasaColors.darkTertiaryInk   : KasaColors.lightTertiaryInk,
      tertiaryContainer: isDark ? KasaColors.darkTertiary.withValues(alpha: 0.2)
                                : KasaColors.lightTertiary.withValues(alpha: 0.15),
      onTertiaryContainer: isDark ? KasaColors.darkTertiary     : KasaColors.lightTertiary,

      // Surfaces
      surface:                     isDark ? KasaColors.darkCard    : KasaColors.lightCard,
      onSurface:                   isDark ? KasaColors.darkText    : KasaColors.lightText,
      surfaceContainerHighest:     isDark ? KasaColors.darkElev    : KasaColors.lightElev,
      surfaceContainerHigh:        isDark ? KasaColors.darkElevHigh: KasaColors.lightElevHigh,
      surfaceContainer:            isDark ? KasaColors.darkCard    : KasaColors.lightCard,
      surfaceContainerLow:         isDark ? KasaColors.darkBg      : KasaColors.lightBg,
      surfaceContainerLowest:      isDark ? const Color(0xFF000000): KasaColors.lightBg,
      onSurfaceVariant:            isDark ? KasaColors.darkTextSub : KasaColors.lightTextSub,

      // Background
      inverseSurface:   isDark ? KasaColors.lightText : KasaColors.darkText,
      onInverseSurface: isDark ? KasaColors.darkText  : KasaColors.lightText,

      // Outline — the stroke color
      outline:        isDark ? KasaColors.darkStroke         : KasaColors.lightStroke,
      outlineVariant: isDark ? KasaColors.darkStroke.withValues(alpha: 0.4)
                             : KasaColors.lightStroke.withValues(alpha: 0.3),

      // Shadow
      shadow: isDark ? KasaColors.darkShadow : KasaColors.lightShadow,

      // Scrim / status bar overlay
      scrim: Colors.black,

      // Error
      error:   isDark ? KasaColors.darkError  : KasaColors.lightError,
      onError: Colors.white,
      errorContainer:   isDark ? KasaColors.darkError.withValues(alpha: 0.2)
                               : KasaColors.lightError.withValues(alpha: 0.15),
      onErrorContainer: isDark ? KasaColors.darkError : KasaColors.lightError,
    );

    // Typography — Space Grotesk for display, Inter for body
    final base = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    final displayFont = GoogleFonts.spaceGroteskTextTheme(base).copyWith(
      displayLarge:  GoogleFonts.spaceGrotesk(fontSize: 56, fontWeight: FontWeight.w700, letterSpacing: -1.12),
      displayMedium: GoogleFonts.spaceGrotesk(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -0.88),
      displaySmall:  GoogleFonts.spaceGrotesk(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.72),
      headlineLarge: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.56),
      headlineMedium:GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.44),
      headlineSmall: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.36),
      titleLarge:    GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.32),
      titleMedium:   GoogleFonts.inter(fontSize: 14,        fontWeight: FontWeight.w600),
      titleSmall:    GoogleFonts.inter(fontSize: 12,        fontWeight: FontWeight.w600),
      bodyLarge:     GoogleFonts.inter(fontSize: 16,        fontWeight: FontWeight.w500),
      bodyMedium:    GoogleFonts.inter(fontSize: 14,        fontWeight: FontWeight.w500),
      bodySmall:     GoogleFonts.inter(fontSize: 12,        fontWeight: FontWeight.w500),
      labelLarge:    GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.48),
      labelMedium:   GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.44),
      labelSmall:    GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4),
    );
    final textTheme = displayFont.apply(
      bodyColor:    cs.onSurface,
      displayColor: cs.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: cs,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? KasaColors.darkBg : KasaColors.lightBg,

      // Status bar / nav bar
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? KasaColors.darkBg : KasaColors.lightBg,
        foregroundColor: cs.onSurface,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: cs.onSurface,
          fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.36,
        ),
      ),

      // Cards — elevation 0; border + hard shadow applied by KasaCard widget
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KasaRadius.md)),
        margin: EdgeInsets.zero,
      ),

      // Input fields — neo-brutalist block style
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          borderSide: BorderSide(color: cs.outline, width: KasaBorders.card),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          borderSide: BorderSide(color: cs.outline, width: KasaBorders.card),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          borderSide: BorderSide(color: cs.secondary, width: KasaBorders.button),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          borderSide: BorderSide(color: cs.error, width: KasaBorders.card),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          borderSide: BorderSide(color: cs.error, width: KasaBorders.button),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.44),
      ),

      // Elevated buttons — salmon fill, 3px border, 24px radius, hard shadow via wrapper
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KasaRadius.xl),
            side: BorderSide(color: cs.outline, width: KasaBorders.button),
          ),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          textStyle: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.28),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.secondary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KasaRadius.xl),
          ),
          side: BorderSide(color: cs.outline, width: KasaBorders.card),
          foregroundColor: cs.onSurface,
          textStyle: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KasaRadius.xl),
          side: BorderSide(color: cs.outline, width: KasaBorders.card),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KasaRadius.pill),
          side: BorderSide(color: cs.outline, width: KasaBorders.card),
        ),
        labelStyle: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.04),
      ),

      dividerTheme: const DividerThemeData(
        thickness: 0,
        space: 0,
        color: Colors.transparent,
      ),

      // Bottom nav — handled by custom KasaBottomNav widget in router.dart
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: cs.secondary,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.onSecondary, size: 22);
          }
          return IconThemeData(color: cs.onSurfaceVariant, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSecondary);
          }
          return GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant);
        }),
      ),
    );
  }
}
