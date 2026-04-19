import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/kasa_tokens.dart';

// ─── KasaCard ─────────────────────────────────────────────────────────────────
// 2px border + 4px hard-edge shadow (blurRadius 0). No soft shadow.

enum KasaCardAccent { none, primary, secondary, tertiary, elevated }

class KasaCard extends StatelessWidget {
  const KasaCard({
    super.key,
    required this.child,
    this.accent = KasaCardAccent.none,
    this.padding = const EdgeInsets.all(16),
    this.radius = KasaRadius.md,
    this.showShadow = true,
    this.onTap,
  });

  final Widget child;
  final KasaCardAccent accent;
  final EdgeInsets padding;
  final double radius;
  final bool showShadow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final fill = switch (accent) {
      KasaCardAccent.primary   => cs.primary,
      KasaCardAccent.secondary => cs.secondary,
      KasaCardAccent.tertiary  => cs.tertiary,
      KasaCardAccent.elevated  => cs.surfaceContainerHighest,
      KasaCardAccent.none      => cs.surface,
    };
    final ink = switch (accent) {
      KasaCardAccent.primary   => cs.onPrimary,
      KasaCardAccent.secondary => cs.onSecondary,
      KasaCardAccent.tertiary  => cs.onTertiary,
      _                        => cs.onSurface,
    };

    Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
        boxShadow: showShadow
            ? [BoxShadow(
                color: cs.kasaShadow,
                offset: const Offset(KasaBorders.shadow, KasaBorders.shadow),
                blurRadius: 0,
              )]
            : null,
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: ink), child: child),
    );

    if (onTap != null) {
      box = GestureDetector(
        onTap: onTap,
        child: box,
      );
    }
    return box;
  }
}

// ─── KasaChip ─────────────────────────────────────────────────────────────────

enum KasaChipVariant { neutral, primary, secondary, tertiary }

class KasaChip extends StatelessWidget {
  const KasaChip({
    super.key,
    required this.label,
    this.variant = KasaChipVariant.neutral,
    this.small = false,
    this.leading,
  });

  final String label;
  final KasaChipVariant variant;
  final bool small;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = switch (variant) {
      KasaChipVariant.primary   => cs.primary,
      KasaChipVariant.secondary => cs.secondary,
      KasaChipVariant.tertiary  => cs.tertiary,
      KasaChipVariant.neutral   => Colors.transparent,
    };
    final ink = switch (variant) {
      KasaChipVariant.primary   => cs.onPrimary,
      KasaChipVariant.secondary => cs.onSecondary,
      KasaChipVariant.tertiary  => cs.onTertiary,
      KasaChipVariant.neutral   => cs.onSurface,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KasaRadius.pill),
        border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: small ? 10 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04,
              color: ink,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── KasaButton ───────────────────────────────────────────────────────────────

enum KasaButtonVariant { primary, secondary, tertiary, ghost }

class KasaButton extends StatelessWidget {
  const KasaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = KasaButtonVariant.primary,
    this.fullWidth = true,
    this.leading,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final KasaButtonVariant variant;
  final bool fullWidth;
  final Widget? leading;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = switch (variant) {
      KasaButtonVariant.primary   => cs.primary,
      KasaButtonVariant.secondary => cs.secondary,
      KasaButtonVariant.tertiary  => cs.tertiary,
      KasaButtonVariant.ghost     => Colors.transparent,
    };
    final ink = switch (variant) {
      KasaButtonVariant.primary   => cs.onPrimary,
      KasaButtonVariant.secondary => cs.onSecondary,
      KasaButtonVariant.tertiary  => cs.onTertiary,
      KasaButtonVariant.ghost     => cs.onSurface,
    };

    final disabled = onTap == null || isLoading;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(KasaRadius.xl),
            border: Border.all(color: cs.kasaStroke, width: KasaBorders.button),
            boxShadow: variant != KasaButtonVariant.ghost && !disabled
                ? [BoxShadow(
                    color: cs.kasaShadow,
                    offset: const Offset(KasaBorders.shadow, KasaBorders.shadow),
                    blurRadius: 0,
                  )]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(color: ink, strokeWidth: 2.5),
                )
              else ...[
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.28,
                    color: ink,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── KpiCard ──────────────────────────────────────────────────────────────────
// Large-number KPI tile used in Bento grid dashboards.

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.accent = KasaCardAccent.none,
    this.expand = false,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final String? sub;
  final KasaCardAccent accent;
  final bool expand;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = switch (accent) {
      KasaCardAccent.primary   => cs.onPrimary,
      KasaCardAccent.secondary => cs.onSecondary,
      KasaCardAccent.tertiary  => cs.onTertiary,
      _                        => cs.onSurface,
    };

    return KasaCard(
      accent: accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 0.04, color: ink.withValues(alpha: 0.75),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 48, fontWeight: FontWeight.w700,
              letterSpacing: -0.96, color: ink, height: 1,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: ink.withValues(alpha: 0.7),
            )),
          ],
        ],
      ),
    );
  }
}

// ─── KasaAvatar ───────────────────────────────────────────────────────────────

class KasaAvatar extends StatelessWidget {
  const KasaAvatar({super.key, required this.name, this.size = 40, this.accent = KasaCardAccent.primary});
  final String name;
  final double size;
  final KasaCardAccent accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = name.trim().split(' ')
        .where((s) => s.isNotEmpty).take(2)
        .map((s) => s[0].toUpperCase()).join();
    final (bg, ink) = switch (accent) {
      KasaCardAccent.secondary => (cs.secondary, cs.onSecondary),
      KasaCardAccent.tertiary  => (cs.tertiary, cs.onTertiary),
      _                        => (cs.primary, cs.onPrimary),
    };
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.spaceGrotesk(
          fontSize: size * 0.38, fontWeight: FontWeight.w700,
          color: ink, letterSpacing: -0.02,
        ),
      ),
    );
  }
}
