import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Deep teal seed — signals trust, growth, financial health
  static const _seed = Color(0xFF00695C);
  static const _errorRed = Color(0xFFB3261E);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final cs = ColorScheme.fromSeed(
      seedColor: _seed,
      error: _errorRed,
      brightness: brightness,
    );

    final textTheme = GoogleFonts.poppinsTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      textTheme: textTheme,

      // AppBar — flat, surface-colored, left-aligned title
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: cs.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Cards — elevation 0, tinted surface, 16dp radius
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),

      // Input fields — filled, rounded, no outline border
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),

      // Primary buttons — stadium shape, 56dp tall, full width
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: const StadiumBorder(),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Outlined buttons
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: const StadiumBorder(),
          side: BorderSide(color: cs.outline),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 2,
        shape: const StadiumBorder(),
      ),

      // Chips
      chipTheme: const ChipThemeData(
        shape: StadiumBorder(),
        side: BorderSide.none,
      ),

      // Bottom navigation
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.onPrimaryContainer);
          }
          return IconThemeData(color: cs.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),

      // Dividers — subtle
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// Semantic status colors for invoice/payment states.
extension RentalColors on ColorScheme {
  Color get statusPaid => const Color(0xFF2E7D32);
  Color get statusPaidBg => const Color(0xFFE8F5E9);
  Color get statusOverdue => const Color(0xFFB71C1C);
  Color get statusOverdueBg => const Color(0xFFFFEBEE);
  Color get statusPending => const Color(0xFFF57F17);
  Color get statusPendingBg => const Color(0xFFFFF8E1);
  Color get statusVacant => const Color(0xFF0277BD);
  Color get statusVacantBg => const Color(0xFFE1F5FE);
  Color get statusCancelled => const Color(0xFF546E7A);
  Color get statusCancelledBg => const Color(0xFFECEFF1);
}
