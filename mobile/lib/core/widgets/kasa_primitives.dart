import 'package:flutter/material.dart';
import '../theme/kasa_fonts.dart';

import '../theme/kasa_tokens.dart';

// Loading skeletons live beside the primitives so any screen importing the
// primitives can use them without a second import.
export 'kasa_skeleton.dart';

/// Press feedback for tappable surfaces.
///
/// WHY opacity and not a scale or offset: Kasa 2.0 is flat, so there is no
/// shadow to travel along. Motion is opacity only, 150 ms, and skipped when the
/// viewer asked for reduced motion (the dim still shows, it just does not fade).
class _PressableSurface extends StatefulWidget {
  const _PressableSurface({required this.onTap, required this.builder});

  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool isPressed) builder;

  @override
  State<_PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<_PressableSurface> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: KasaMotion.of(context, KasaMotion.fast),
        curve: KasaMotion.curve,
        opacity: _pressed ? 0.7 : 1.0,
        child: widget.builder(context, _pressed),
      ),
    );
  }
}

// ─── KasaCard ─────────────────────────────────────────────────────────────────
// Flat surface, 1px hairline border. [showShadow] adds the soft raised shadow
// and is off by default: shadows are for sheets and menus, not every card.

enum KasaCardAccent { none, primary, secondary, tertiary, elevated }

class KasaCard extends StatelessWidget {
  const KasaCard({
    super.key,
    required this.child,
    this.accent = KasaCardAccent.none,
    this.padding = const EdgeInsets.all(16),
    this.radius = KasaRadius.md,
    this.showShadow = false,
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
      KasaCardAccent.primary => cs.primary,
      KasaCardAccent.secondary => cs.secondary,
      KasaCardAccent.tertiary => cs.tertiary,
      KasaCardAccent.elevated => cs.surfaceContainerHighest,
      KasaCardAccent.none => cs.surface,
    };
    final ink = switch (accent) {
      KasaCardAccent.primary => cs.onPrimary,
      KasaCardAccent.secondary => cs.onSecondary,
      KasaCardAccent.tertiary => cs.onTertiary,
      _ => cs.onSurface,
    };

    Widget surface(bool isPressed) => Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
            boxShadow: showShadow ? KasaElevation.raised(cs) : null,
          ),
          child:
              DefaultTextStyle.merge(style: TextStyle(color: ink), child: child),
        );

    if (onTap == null) return surface(false);

    return _PressableSurface(
      onTap: onTap!,
      builder: (context, isPressed) => surface(isPressed),
    );
  }
}

// ─── KasaChip ─────────────────────────────────────────────────────────────────
// Generic label chip. For rent/repair STATE use [KasaStatusChip] instead: it
// carries the dot + word pairing the status colours require.

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
      KasaChipVariant.primary => cs.primaryContainer,
      KasaChipVariant.secondary => cs.surfaceContainerHighest,
      KasaChipVariant.tertiary => cs.tertiary,
      KasaChipVariant.neutral => Colors.transparent,
    };
    final ink = switch (variant) {
      KasaChipVariant.tertiary => cs.onTertiary,
      _ => cs.onSurface,
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
            label,
            style: KasaFont.sans(
              fontSize: small ? 12 : 13,
              fontWeight: FontWeight.w500,
              color: ink,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paid / Due / Overdue / Vacant / Notice. Muted colour + a dot + a WORD, so
/// colour is never the only signal (WCAG 1.4.1).
class KasaStatusChip extends StatelessWidget {
  const KasaStatusChip({super.key, required this.kind, required this.label});

  final KasaStatusKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final pair = Theme.of(context).colorScheme.statusPair(kind);

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: pair.bg,
        borderRadius: BorderRadius.circular(KasaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: pair.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: KasaFont.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: pair.fg,
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

    // Primary is the accent fill; secondary is an outlined surface (it used to
    // be a second loud colour); ghost is text only.
    final bg = switch (variant) {
      KasaButtonVariant.primary => cs.primary,
      KasaButtonVariant.secondary => cs.surface,
      KasaButtonVariant.tertiary => cs.tertiary,
      KasaButtonVariant.ghost => Colors.transparent,
    };
    final ink = switch (variant) {
      KasaButtonVariant.primary => cs.onPrimary,
      KasaButtonVariant.tertiary => cs.onTertiary,
      _ => cs.onSurface,
    };
    final border = switch (variant) {
      KasaButtonVariant.secondary => cs.kasaStrokeStrong,
      _ => Colors.transparent,
    };

    final disabled = onTap == null || isLoading;

    // WHY the busy state keeps the label's space: swapping the label for a
    // spinner at a different size makes the button jump. The spinner sits over
    // an invisible label so the width and height stay put.
    Widget content() {
      final text = Text(
        label,
        style: KasaFont.sans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
          height: 1.1,
        ),
      );
      return Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: isLoading ? 0 : 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                text,
              ],
            ),
          ),
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: ink, strokeWidth: 2.5),
            ),
        ],
      );
    }

    Widget face() => Opacity(
          opacity: onTap == null && !isLoading ? 0.5 : 1.0,
          child: Container(
            width: fullWidth ? double.infinity : null,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(KasaRadius.md),
              border: Border.all(color: border, width: KasaBorders.button),
            ),
            child: content(),
          ),
        );

    return Semantics(
      button: true,
      enabled: !disabled,
      child: disabled
          ? face()
          : _PressableSurface(onTap: onTap!, builder: (context, _) => face()),
    );
  }
}

// ─── KpiCard ──────────────────────────────────────────────────────────────────
// Large-number tile. Numbers are the hero: tabular figures, calm 34pt, sentence
// case label (no uppercase eyebrow).

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
      KasaCardAccent.primary => cs.onPrimary,
      KasaCardAccent.secondary => cs.onSecondary,
      KasaCardAccent.tertiary => cs.onTertiary,
      _ => cs.onSurface,
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
                label,
                style: KasaFont.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ink.withValues(alpha: 0.75),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8),
          Text(
            value,
            style: KasaFont.sans(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.68,
              color: ink,
              height: 1.1,
              fontFeatures: KasaType.tabular,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: KasaFont.sans(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: ink.withValues(alpha: 0.7),
                fontFeatures: KasaType.tabular,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── KasaAvatar ───────────────────────────────────────────────────────────────
// Neutral by default (grey tile, muted initials). Non-default accents still
// fill, for the few places that mean something by it.

class KasaAvatar extends StatelessWidget {
  const KasaAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.accent = KasaCardAccent.primary,
  });

  final String name;
  final double size;
  final KasaCardAccent accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = name
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();
    final (bg, ink) = switch (accent) {
      KasaCardAccent.secondary => (cs.secondary, cs.onSecondary),
      KasaCardAccent.tertiary => (cs.tertiary, cs.onTertiary),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: KasaFont.sans(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
    );
  }
}

// ─── KasaContentSwitcher ──────────────────────────────────────────────────────

/// Crossfades between a screen's loading, error and loaded states.
///
/// WHY shared rather than inline at each screen: the skeleton -> content swap
/// should feel identical everywhere, so the duration and curve live in one
/// place (KasaMotion) instead of drifting per screen.
class KasaContentSwitcher extends StatelessWidget {
  const KasaContentSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Skipped entirely when the viewer has asked for less motion; the content
    // still swaps, it just does not fade.
    if (MediaQuery.of(context).disableAnimations) return child;

    return AnimatedSwitcher(
      duration: KasaMotion.slow,
      switchInCurve: KasaMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      child: child,
    );
  }
}
