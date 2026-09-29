import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/kasa_fonts.dart';

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
      outline:        isDark ? KasaColors.darkStrokeStrong : KasaColors.lightStrokeStrong,
      outlineVariant: isDark ? KasaColors.darkStroke : KasaColors.lightStroke,

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
    final displayFont = base.apply(fontFamily: KasaFont.sansFamily).copyWith(
      displayLarge:  KasaFont.sans(fontSize: 56, fontWeight: FontWeight.w600, letterSpacing: -1.12),
      displayMedium: KasaFont.sans(fontSize: 44, fontWeight: FontWeight.w600, letterSpacing: -0.88),
      displaySmall:  KasaFont.sans(fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -0.72),
      headlineLarge: KasaFont.sans(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.56),
      headlineMedium:KasaFont.sans(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.44),
      headlineSmall: KasaFont.sans(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.36),
      titleLarge:    KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.32),
      titleMedium:   KasaFont.sans(fontSize: 14,        fontWeight: FontWeight.w600),
      titleSmall:    KasaFont.sans(fontSize: 12,        fontWeight: FontWeight.w600),
      bodyLarge:     KasaFont.sans(fontSize: 16,        fontWeight: FontWeight.w500),
      bodyMedium:    KasaFont.sans(fontSize: 14,        fontWeight: FontWeight.w500),
      bodySmall:     KasaFont.sans(fontSize: 12,        fontWeight: FontWeight.w500),
      labelLarge:    KasaFont.sans(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48),
      labelMedium:   KasaFont.sans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.44),
      labelSmall:    KasaFont.sans(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4),
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
        titleTextStyle: KasaFont.sans(
          color: cs.onSurface,
          fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.36,
        ),
      ),

      // Cards — elevation 0; border + hard shadow applied by KasaCard widget
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KasaRadius.md)),
        margin: EdgeInsets.zero,
      ),

      // Input fields — flat, strong hairline; 2px ring on focus
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
          borderSide: BorderSide(color: cs.onSurface, width: KasaBorders.focus),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          borderSide: BorderSide(color: cs.error, width: KasaBorders.card),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          borderSide: BorderSide(color: cs.error, width: KasaBorders.focus),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: KasaFont.sans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.44),
      ),

      // Elevated buttons — salmon fill, 3px border, 24px radius, hard shadow via wrapper
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KasaRadius.md),
            side: BorderSide.none,
          ),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          textStyle: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.28),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.secondary,
          textStyle: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KasaRadius.md),
          ),
          side: BorderSide(color: cs.outline, width: KasaBorders.card),
          foregroundColor: cs.onSurface,
          textStyle: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KasaRadius.md),
          side: BorderSide(color: cs.outline, width: KasaBorders.card),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KasaRadius.pill),
          side: BorderSide(color: cs.outline, width: KasaBorders.card),
        ),
        labelStyle: KasaFont.sans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.04),
      ),

      dividerTheme: const DividerThemeData(
        thickness: 0,
        space: 0,
        color: Colors.transparent,
      ),

      // Bottom nav — KasaNavBar (core/widgets/kasa_nav_bar.dart). Flat surface,
      // accent pill behind the current tab, a word under every icon. The hairline
      // top border is drawn by KasaNavBar itself.
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.primaryContainer,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? cs.primary : cs.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return KasaFont.sans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? cs.onSurface : cs.onSurfaceVariant,
          );
        }),
      ),
    );
  }
}
