import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/kasa_tokens.dart';

// ─── House mark ────────────────────────────────────────────────────────────────

class KasaMark extends StatelessWidget {
  const KasaMark({super.key, this.size = 48, this.showShadow = true});
  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = size * (80 / 96);
    return SizedBox(
      width: size,
      height: h,
      child: CustomPaint(
        painter: _HousePainter(
          houseFill: cs.kasaHouseFill,
          shadow: showShadow ? cs.kasaShadow : Colors.transparent,
          shadowOffset: KasaBorders.shadow,
        ),
      ),
    );
  }
}

class _HousePainter extends CustomPainter {
  const _HousePainter({
    required this.houseFill,
    required this.shadow,
    required this.shadowOffset,
  });

  final Color houseFill;
  final Color shadow;
  final double shadowOffset;

  // Build the house-with-key path normalised to viewBox 96×80.
  Path _buildPath() {
    final p = Path()
      // Outer house silhouette (clockwise from bottom-left)
      ..moveTo(12, 74)
      ..quadraticBezierTo(8, 74, 8, 70)
      ..lineTo(8, 32)
      ..quadraticBezierTo(8, 30, 9.5, 28.5)
      ..lineTo(46, 4)
      ..quadraticBezierTo(48, 2.5, 50, 4)
      ..lineTo(86.5, 28.5)
      ..quadraticBezierTo(88, 30, 88, 32)
      ..lineTo(88, 70)
      ..quadraticBezierTo(88, 74, 84, 74)
      ..close()
      // Key bow — full circle at (48, 42) r=6.5
      ..addOval(Rect.fromCircle(center: const Offset(48, 42), radius: 6.5))
      // Key shaft
      ..addRect(const Rect.fromLTRB(45.5, 42, 50.5, 68))
      // Tooth 1
      ..addRect(const Rect.fromLTRB(50.5, 58, 55.5, 60.5))
      // Tooth 2
      ..addRect(const Rect.fromLTRB(50.5, 62.5, 55.5, 65));
    p.fillType = PathFillType.evenOdd;
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 96;
    final scaleY = size.height / 80;
    final path = _buildPath();

    // Hard-edge shadow — draw offset copy first
    if (shadow != Colors.transparent) {
      canvas.save();
      canvas.translate(shadowOffset, shadowOffset);
      canvas.scale(scaleX, scaleY);
      canvas.drawPath(path, Paint()..color = shadow);
      canvas.restore();
    }

    // Main house
    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawPath(path, Paint()..color = houseFill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HousePainter old) =>
      old.houseFill != houseFill ||
      old.shadow != shadow ||
      old.shadowOffset != shadowOffset;
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
            fontWeight: FontWeight.w900,
            color: cs.kasaKColor,
            letterSpacing: -0.01 * fontSize,
            height: 0.9,
          ),
        ),
        TextSpan(
          text: 'ASA',
          style: GoogleFonts.outfit(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: cs.kasaAsaColor,
            letterSpacing: -0.01 * fontSize,
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
