import 'package:flutter/material.dart';

class KasaColors {
  KasaColors._();

  // ── Dark palette ───────────────────────────────────────────────────────────
  static const darkBg           = Color(0xFF0E0E13);
  static const darkCard         = Color(0xFF19191F);
  static const darkElev         = Color(0xFF25252C);
  static const darkElevHigh     = Color(0xFF1F1F25);
  static const darkText         = Color(0xFFF0EDF4);
  static const darkTextSub      = Color(0xFFACAAB1);
  static const darkStroke       = Color(0xFF48474D);
  static const darkShadow       = Color(0xFF000000);

  static const darkPrimary      = Color(0xFFFF8E7F);
  static const darkPrimaryInk   = Color(0xFF2C0000);
  static const darkSecondary    = Color(0xFF8496FF);
  static const darkSecondaryInk = Color(0xFF052496);
  static const darkTertiary     = Color(0xFFFFEDB3);
  static const darkTertiaryInk  = Color(0xFF4A3D00);
  static const darkError        = Color(0xFFFF6E84);

  // Logo tokens
  static const darkHouseFill    = Color(0xFF8496FF);
  static const darkKColor       = Color(0xFFFF8E7F);
  static const darkAsaColor     = Color(0xFFF0EDF4);

  // ── Light palette ──────────────────────────────────────────────────────────
  static const lightBg          = Color(0xFFF5F2ED);
  static const lightCard        = Color(0xFFFFFFFF);
  static const lightElev        = Color(0xFFEBE7DF);
  static const lightElevHigh    = Color(0xFFE0DCD2);
  static const lightText        = Color(0xFF1A1A1F);
  static const lightTextSub     = Color(0xFF5A5962);
  static const lightStroke      = Color(0xFF1A1A1F);
  static const lightShadow      = Color(0xFF1A1A1F);

  static const lightPrimary     = Color(0xFFFF7A66);
  static const lightPrimaryInk  = Color(0xFF2C0000);
  static const lightSecondary   = Color(0xFF5868E0);
  static const lightSecondaryInk = Color(0xFFF5F2ED);
  static const lightTertiary    = Color(0xFFF5C842);
  static const lightTertiaryInk = Color(0xFF4A3D00);
  static const lightError       = Color(0xFFD32F2F);

  // Logo tokens
  static const lightHouseFill   = Color(0xFF2F3FB8);
  static const lightKColor      = Color(0xFFFF7A66);
  static const lightAsaColor    = Color(0xFF1A1A1F);
}

class KasaRadius {
  KasaRadius._();
  static const sm   = 12.0;
  static const md   = 16.0;
  static const lg   = 20.0;
  static const xl   = 24.0;
  static const pill = 999.0;
}

class KasaBorders {
  KasaBorders._();
  static const card    = 2.0;
  static const button  = 3.0;
  static const shadow  = 4.0; // hard-edge offset — blurRadius always 0
}

/// Access Kasa-specific colors from any ColorScheme.
extension KasaColorScheme on ColorScheme {
  // Stroke / shadow resolve per theme brightness.
  Color get kasaStroke  => brightness == Brightness.dark
      ? KasaColors.darkStroke  : KasaColors.lightStroke;
  Color get kasaShadow  => brightness == Brightness.dark
      ? KasaColors.darkShadow  : KasaColors.lightShadow;
  Color get kasaBg      => brightness == Brightness.dark
      ? KasaColors.darkBg      : KasaColors.lightBg;
  Color get kasaCard    => brightness == Brightness.dark
      ? KasaColors.darkCard    : KasaColors.lightCard;
  Color get kasaElev    => brightness == Brightness.dark
      ? KasaColors.darkElev    : KasaColors.lightElev;
  Color get kasaTextSub => brightness == Brightness.dark
      ? KasaColors.darkTextSub : KasaColors.lightTextSub;

  // Tertiary ink (dark text on yellow/amber fills)
  Color get tertiaryInk => brightness == Brightness.dark
      ? KasaColors.darkTertiaryInk : KasaColors.lightTertiaryInk;

  // Status chips — match the design bundle's color convention
  Color get statusPaid       => primary;
  Color get statusPaidInk    => onPrimary;
  Color get statusPaidBg     => primary.withValues(alpha: 0.15);
  Color get statusOverdue    => tertiary;
  Color get statusOverdueInk => tertiaryInk;
  Color get statusOverdueBg  => tertiary.withValues(alpha: 0.15);
  Color get statusPending    => secondary;
  Color get statusPendingInk => onSecondary;
  Color get statusPendingBg  => secondary.withValues(alpha: 0.15);
  Color get statusVacant     => brightness == Brightness.dark ? const Color(0xFFFFEDB3) : const Color(0xFFF5C842);
  Color get statusVacantBg   => statusVacant.withValues(alpha: 0.15);
  Color get statusCancelled  => brightness == Brightness.dark ? const Color(0xFFACAAB1) : const Color(0xFF5A5962);
  Color get statusCancelledBg => statusCancelled.withValues(alpha: 0.12);

  // Logo
  Color get kasaHouseFill => brightness == Brightness.dark
      ? KasaColors.darkHouseFill : KasaColors.lightHouseFill;
  Color get kasaKColor    => brightness == Brightness.dark
      ? KasaColors.darkKColor    : KasaColors.lightKColor;
  Color get kasaAsaColor  => brightness == Brightness.dark
      ? KasaColors.darkAsaColor  : KasaColors.lightAsaColor;
}

/// Payment-channel and third-party brand colors.
///
/// WHY these are fixed rather than theme-driven: they identify an external
/// brand (M-Pesa green, WhatsApp green) or a payment rail users recognise by
/// colour. They stay constant across light and dark so the channel stays
/// recognisable; only the surface behind them changes. Each is checked to hold
/// contrast on both the cream and near-black grounds.
class KasaChannel {
  KasaChannel._();

  static const mpesa    = Color(0xFF43A047); // M-Pesa / STK push
  static const paybill  = Color(0xFF00897B); // Lipa na M-Pesa paybill
  static const bank     = Color(0xFF1565C0); // Bank transfer
  static const cash     = Color(0xFFF57F17); // Cash in hand
  static const whatsapp = Color(0xFF25D366); // WhatsApp delivery channel
}
