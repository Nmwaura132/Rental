import 'package:flutter/material.dart';

/// Kasa 2.0 design tokens — flat surfaces, hairline borders, one accent.
///
/// COMPATIBILITY: every name from the neo-brutalist tokens is kept, only the
/// values changed, so existing call sites compile and pick up the new look.
/// Role mapping (ColorScheme role -> what it means now):
///   primary    -> the single accent; actions and the current tab only
///   secondary  -> strong neutral (ink on light, paper on dark); replaces the
///                 old periwinkle fill
///   tertiary   -> muted "due" amber tint (fill) with amber ink
///   outline    -> input / secondary-button border (strong hairline)
///   kasaStroke -> card border (soft hairline)
/// Screens that used KasaCardAccent.primary/secondary/tertiary as loud fills
/// still work but should move to KasaCardAccent.none in the screen sweep.
class KasaColors {
  KasaColors._();

  // ── Dark palette ───────────────────────────────────────────────────────────
  static const darkBg = Color(0xFF0D0E10);
  static const darkCard = Color(0xFF16171A);
  static const darkElev = Color(0xFF1E2024);
  static const darkElevHigh = Color(0xFF26282D);
  static const darkText = Color(0xFFEDEEF0);
  static const darkTextSub = Color(0xFF9DA1A9);
  static const darkStroke = Color(0xFF26282D); // hairline (cards)
  static const darkStrokeStrong = Color(0xFF3A3D44); // inputs, outlined buttons
  static const darkShadow = Color(0xFF000000);

  static const darkPrimary = Color(0xFFFF8A75);
  static const darkPrimaryInk = Color(0xFF1E0C08);
  static const darkSecondary = Color(0xFFEDEEF0);
  static const darkSecondaryInk = Color(0xFF0D0E10);
  static const darkTertiary = Color(0xFF29230F);
  static const darkTertiaryInk = Color(0xFFE3C06F);
  static const darkError = Color(0xFFF39C89);

  static const darkSkeleton = Color(0xFF22242A);
  static const darkSkeletonHi = Color(0xFF2C2F36);

  // Logo tokens — the K stays brand coral on both themes.
  static const darkKColor = Color(0xFFFF7A66);
  static const darkAsaColor = Color(0xFFEDEEF0);

  // ── Light palette ──────────────────────────────────────────────────────────
  static const lightBg = Color(0xFFF6F6F4);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightElev = Color(0xFFF0F0ED);
  static const lightElevHigh = Color(0xFFE4E3DF);
  static const lightText = Color(0xFF15161A);
  static const lightTextSub = Color(0xFF5E6168);
  static const lightStroke = Color(0xFFE4E3DF); // hairline (cards)
  static const lightStrokeStrong = Color(0xFFCFCEC9); // inputs, outlined buttons
  static const lightShadow = Color(0xFF15161A);

  // #C2452F, not brand coral: white on #FF7A66 is ~2.6:1, on #C2452F ~5.0:1.
  static const lightPrimary = Color(0xFFC2452F);
  static const lightPrimaryInk = Color(0xFFFFFFFF);
  static const lightSecondary = Color(0xFF15161A);
  static const lightSecondaryInk = Color(0xFFF6F6F4);
  static const lightTertiary = Color(0xFFF5EEDC);
  static const lightTertiaryInk = Color(0xFF7A5A0F);
  static const lightError = Color(0xFFA3321F);

  static const lightSkeleton = Color(0xFFECECE8);
  static const lightSkeletonHi = Color(0xFFF8F8F6);

  // Logo tokens
  static const lightKColor = Color(0xFFFF7A66);
  static const lightAsaColor = Color(0xFF15161A);
}

/// Corner radii. Cards and buttons 12, inputs 10, sheets 20, chips/avatars full.
class KasaRadius {
  KasaRadius._();
  static const sm = 10.0;
  static const md = 12.0;
  static const lg = 14.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

class KasaBorders {
  KasaBorders._();
  static const hairline = 1.0;
  static const card = 1.0;
  static const button = 1.0;
  static const focus = 2.0; // focused input ring

  /// RETIRED. The hard-edge offset shadow is gone; kept at 0 so legacy call
  /// sites (`Offset(KasaBorders.shadow, KasaBorders.shadow)`, blurRadius 0)
  /// draw an invisible shadow instead of failing to compile. Delete with the
  /// screen sweep.
  static const shadow = 0.0;
}

/// 4-pt spacing scale. Side gutter is 16.
class KasaSpace {
  KasaSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const gutter = lg;
}

/// Motion: subtle, 150-250 ms, opacity/translate only.
class KasaMotion {
  KasaMotion._();
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;

  /// Zero when the viewer asked for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

/// Elevation: hairline (level 0, no shadow) or raised (sheets, menus only).
class KasaElevation {
  KasaElevation._();
  static List<BoxShadow> raised(ColorScheme cs) {
    final dark = cs.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: cs.kasaShadow.withValues(alpha: dark ? 0.5 : 0.08),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: cs.kasaShadow.withValues(alpha: dark ? 0.4 : 0.06),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }
}

/// Numbers are the hero: money and counts use tabular figures so columns align.
class KasaType {
  KasaType._();
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextStyle money(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -size * 0.02,
        height: 1.1,
        color: color,
        fontFeatures: tabular,
      );

  static TextStyle get moneyXl => money(34);
  static TextStyle get moneyL => money(22);
}

/// Status colours: muted, always shown with a dot AND a word.
/// [occupied] is the plain "someone lives here": neutral, with none of the
/// payment colours. A caretaker sees this in place of paid, due and overdue.
enum KasaStatusKind { paid, due, overdue, vacant, notice, occupied }

typedef KasaStatusPair = ({Color fg, Color bg});

class KasaStatus {
  KasaStatus._();

  static const _light = <KasaStatusKind, KasaStatusPair>{
    KasaStatusKind.paid: (fg: Color(0xFF1E6A3E), bg: Color(0xFFE6F2EA)),
    KasaStatusKind.due: (fg: Color(0xFF7A5A0F), bg: Color(0xFFF5EEDC)),
    KasaStatusKind.overdue: (fg: Color(0xFFA3321F), bg: Color(0xFFF9E7E3)),
    KasaStatusKind.vacant: (fg: Color(0xFF4A5261), bg: Color(0xFFECEEF2)),
    KasaStatusKind.notice: (fg: Color(0xFF4E3F9E), bg: Color(0xFFECEAF8)),
    KasaStatusKind.occupied: (fg: Color(0xFF5E6168), bg: Color(0xFFF0F0ED)),
  };

  static const _dark = <KasaStatusKind, KasaStatusPair>{
    KasaStatusKind.paid: (fg: Color(0xFF7CCB9A), bg: Color(0xFF15241B)),
    KasaStatusKind.due: (fg: Color(0xFFE3C06F), bg: Color(0xFF29230F)),
    KasaStatusKind.overdue: (fg: Color(0xFFF39C89), bg: Color(0xFF2E1814)),
    KasaStatusKind.vacant: (fg: Color(0xFFA9B0BC), bg: Color(0xFF1F2227)),
    KasaStatusKind.notice: (fg: Color(0xFFB6ABF2), bg: Color(0xFF211D35)),
    KasaStatusKind.occupied: (fg: Color(0xFF9DA1A9), bg: Color(0xFF1E2024)),
  };

  static KasaStatusPair of(KasaStatusKind kind, Brightness brightness) =>
      (brightness == Brightness.dark ? _dark : _light)[kind]!;
}

/// Access Kasa-specific colors from any ColorScheme.
extension KasaColorScheme on ColorScheme {
  bool get _isDark => brightness == Brightness.dark;

  Color get kasaStroke =>
      _isDark ? KasaColors.darkStroke : KasaColors.lightStroke;
  Color get kasaStrokeStrong =>
      _isDark ? KasaColors.darkStrokeStrong : KasaColors.lightStrokeStrong;
  Color get kasaShadow =>
      _isDark ? KasaColors.darkShadow : KasaColors.lightShadow;
  Color get kasaBg => _isDark ? KasaColors.darkBg : KasaColors.lightBg;
  Color get kasaCard => _isDark ? KasaColors.darkCard : KasaColors.lightCard;
  Color get kasaElev => _isDark ? KasaColors.darkElev : KasaColors.lightElev;
  Color get kasaTextSub =>
      _isDark ? KasaColors.darkTextSub : KasaColors.lightTextSub;

  Color get kasaSkeleton =>
      _isDark ? KasaColors.darkSkeleton : KasaColors.lightSkeleton;
  Color get kasaSkeletonHi =>
      _isDark ? KasaColors.darkSkeletonHi : KasaColors.lightSkeletonHi;

  // Tertiary ink (amber text on the due tint)
  Color get tertiaryInk =>
      _isDark ? KasaColors.darkTertiaryInk : KasaColors.lightTertiaryInk;

  KasaStatusPair statusPair(KasaStatusKind kind) =>
      KasaStatus.of(kind, brightness);

  // Status colours. `*Ink` is text on a SOLID status fill; `*Bg` is the tint.
  Color get statusPaid => statusPair(KasaStatusKind.paid).fg;
  Color get statusPaidInk => statusPair(KasaStatusKind.paid).bg;
  Color get statusPaidBg => statusPair(KasaStatusKind.paid).bg;
  Color get statusDue => statusPair(KasaStatusKind.due).fg;
  Color get statusDueBg => statusPair(KasaStatusKind.due).bg;
  Color get statusOverdue => statusPair(KasaStatusKind.overdue).fg;
  Color get statusOverdueInk => statusPair(KasaStatusKind.overdue).bg;
  Color get statusOverdueBg => statusPair(KasaStatusKind.overdue).bg;
  Color get statusNotice => statusPair(KasaStatusKind.notice).fg;
  Color get statusNoticeBg => statusPair(KasaStatusKind.notice).bg;
  // "Pending" is the due state under its old name.
  Color get statusPending => statusDue;
  Color get statusPendingInk => statusDueBg;
  Color get statusPendingBg => statusDueBg;
  Color get statusVacant => statusPair(KasaStatusKind.vacant).fg;
  Color get statusVacantBg => statusPair(KasaStatusKind.vacant).bg;
  Color get statusCancelled => statusVacant;
  Color get statusCancelledBg => statusVacantBg;

  // Logo
  Color get kasaKColor =>
      _isDark ? KasaColors.darkKColor : KasaColors.lightKColor;
  Color get kasaAsaColor =>
      _isDark ? KasaColors.darkAsaColor : KasaColors.lightAsaColor;
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

  static const mpesa = Color(0xFF43A047); // M-Pesa / STK push
  static const paybill = Color(0xFF00897B); // Lipa na M-Pesa paybill
  static const bank = Color(0xFF1565C0); // Bank transfer
  static const cash = Color(0xFFF57F17); // Cash in hand
  static const whatsapp = Color(0xFF25D366); // WhatsApp delivery channel
}
