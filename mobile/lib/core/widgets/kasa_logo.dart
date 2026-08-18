import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/kasa_tokens.dart';

// ─── House mark ────────────────────────────────────────────────────────────────

/// The Kasa mark — "Tenant Link" (concept 04).
///
/// Two half-dwellings interlocking into one home: the landlord side in
/// periwinkle, the tenant side in coral, meeting on a shared tenon. The
/// agreement itself, rather than a roof — a roof alone says real estate, and
/// Kasa is rental operations.
class KasaMark extends StatelessWidget {
  const KasaMark({super.key, this.size = 48, this.showShadow = true});

  final double size;
  final bool showShadow;

  /// Below this the stroke and offset shadow stop resolving and just muddy the
  /// silhouette, so the mark renders as flat colour instead.
  static const _detailCutoff = 32.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final detailed = size >= _detailCutoff;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TenantLinkPainter(
          landlordFill: cs.secondary,
          tenantFill: cs.primary,
          // WHY the stroke is the background colour in dark: it separates the
          // two fills from each other, and on near-black a near-black stroke
          // reads as the gap it is. In light it is the near-black outline.
          stroke: isDark ? KasaColors.darkBg : KasaColors.lightStroke,
          // WHY the shadow inverts: a black offset shadow is invisible on a
          // near-black ground, so dark mode throws a light one instead.
          shadow: (showShadow && detailed)
              ? (isDark ? KasaColors.darkText : KasaColors.lightShadow)
              : Colors.transparent,
          shadowOffset: KasaBorders.shadow,
          drawStroke: detailed,
        ),
      ),
    );
  }
}

class _TenantLinkPainter extends CustomPainter {
  const _TenantLinkPainter({
    required this.landlordFill,
    required this.tenantFill,
    required this.stroke,
    required this.shadow,
    required this.shadowOffset,
    required this.drawStroke,
  });

  final Color landlordFill;
  final Color tenantFill;
  final Color stroke;
  final Color shadow;
  final double shadowOffset;
  final bool drawStroke;

  static const _viewBox = 100.0;

  /// Left half — pitched roof, body, and the tenon reaching right.
  Path _landlordPath() => Path()
    ..moveTo(34, 6)
    ..lineTo(48, 14)
    ..lineTo(48, 42)
    ..lineTo(60, 42)
    ..lineTo(60, 58)
    ..lineTo(48, 58)
    ..lineTo(48, 94)
    ..lineTo(10, 94)
    ..lineTo(10, 40)
    ..close();

  /// Right half — the mortise it locks into.
  Path _tenantPath() => Path()
    ..moveTo(56, 18)
    ..lineTo(94, 40)
    ..lineTo(94, 94)
    ..lineTo(64, 94)
    ..lineTo(64, 64)
    ..lineTo(52, 64)
    ..lineTo(52, 36)
    ..lineTo(64, 36)
    ..lineTo(64, 28)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _viewBox;
    final landlord = _landlordPath();
    final tenant = _tenantPath();

    if (shadow != Colors.transparent) {
      canvas.save();
      canvas.translate(shadowOffset, shadowOffset);
      canvas.scale(scale);
      final paint = Paint()..color = shadow;
      canvas.drawPath(landlord, paint);
      canvas.drawPath(tenant, paint);
      canvas.restore();
    }

    canvas.save();
    canvas.scale(scale);
    canvas.drawPath(landlord, Paint()..color = landlordFill);
    canvas.drawPath(tenant, Paint()..color = tenantFill);

    if (drawStroke) {
      final outline = Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = KasaBorders.button
        ..strokeJoin = StrokeJoin.miter;
      canvas.drawPath(landlord, outline);
      canvas.drawPath(tenant, outline);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TenantLinkPainter old) =>
      old.landlordFill != landlordFill ||
      old.tenantFill != tenantFill ||
      old.stroke != stroke ||
      old.shadow != shadow ||
      old.shadowOffset != shadowOffset ||
      old.drawStroke != drawStroke;
}

// ─── Wordmark ─────────────────────────────────────────────────────────────────

class KasaWordmark extends StatelessWidget {
  const KasaWordmark({super.key, this.fontSize = 32});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'K',
          style: GoogleFonts.outfit(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: cs.kasaKColor,
            letterSpacing: -0.03 * fontSize,
            height: 0.9,
          ),
        ),
        TextSpan(
          text: 'ASA',
          style: GoogleFonts.outfit(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: cs.kasaAsaColor,
            letterSpacing: -0.03 * fontSize,
            height: 0.9,
          ),
        ),
      ]),
    );
  }
}

// ─── Horizontal lockup (mark + wordmark side by side) ─────────────────────────

class KasaLockupHorizontal extends StatelessWidget {
  const KasaLockupHorizontal({super.key, this.markSize = 28});
  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        KasaMark(size: markSize),
        SizedBox(width: markSize * 0.35),
        KasaWordmark(fontSize: markSize * 0.9),
      ],
    );
  }
}

// ─── Stacked lockup (mark above wordmark) ─────────────────────────────────────

class KasaLockupStacked extends StatelessWidget {
  const KasaLockupStacked({super.key, this.markSize = 80});
  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KasaMark(size: markSize),
        SizedBox(height: markSize * 0.2),
        KasaWordmark(fontSize: markSize * 0.42),
      ],
    );
  }
}
