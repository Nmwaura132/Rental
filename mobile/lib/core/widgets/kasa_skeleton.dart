import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/kasa_tokens.dart';

// ─── Loading states ───────────────────────────────────────────────────────────
//
// One skeleton system for every screen, replacing the bare centred spinner.
//
// RULES
//  * A skeleton mirrors the SHAPE of the loaded content (rows stay rows, the
//    summary card stays a card) so nothing jumps when data arrives.
//  * One shimmer sweep per group: [KasaSkeleton] wraps a whole card's worth of
//    blocks. Separate shimmers per row drift out of phase and read as flicker.
//  * The card surface is drawn OUTSIDE the shimmer (the shimmer recolours
//    everything inside it, including backgrounds).
//  * Reduced motion: the sweep stops, the blocks stay as flat placeholders.
//  * Screen readers hear a single "Loading" instead of a swarm of empty boxes.
//  * A button that is busy keeps its spinner (KasaButton.isLoading); a spinner
//    is right for a short action, a skeleton for a screen.

/// Wraps a group of [KasaSkeletonBlock]s in a single shimmer sweep.
class KasaSkeleton extends StatelessWidget {
  const KasaSkeleton({
    super.key,
    required this.child,
    this.semanticLabel = 'Loading',
  });

  final Widget child;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      label: semanticLabel,
      container: true,
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          baseColor: cs.kasaSkeleton,
          highlightColor: cs.kasaSkeletonHi,
          period: const Duration(milliseconds: 1400),
          enabled: !reduceMotion,
          child: child,
        ),
      ),
    );
  }
}

/// A placeholder rectangle. Must sit inside a [KasaSkeleton]: it paints white
/// on purpose, and the shimmer replaces that with the skeleton colours.
class KasaSkeletonBlock extends StatelessWidget {
  const KasaSkeletonBlock({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// The hairline card the skeleton groups sit on.
class _SkeletonSurface extends StatelessWidget {
  const _SkeletonSurface({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(KasaRadius.md),
        border: Border.all(color: cs.kasaStroke, width: KasaBorders.hairline),
      ),
      child: child,
    );
  }
}

/// One list row: leading tile, two text lines, optional trailing block.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.trailingWidth, required this.index});

  final double? trailingWidth;
  final int index;

  @override
  Widget build(BuildContext context) {
    // Vary line widths a little so a stack of rows does not look stamped.
    final titleWidth = 120.0 + (index % 3) * 28;
    final subWidth = 80.0 + (index % 2) * 36;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KasaSpace.lg,
        vertical: KasaSpace.md,
      ),
      child: Row(
        children: [
          const KasaSkeletonBlock(width: 40, height: 40, radius: 10),
          const SizedBox(width: KasaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KasaSkeletonBlock(width: titleWidth, height: 14),
                const SizedBox(height: KasaSpace.sm),
                KasaSkeletonBlock(width: subWidth, height: 12),
              ],
            ),
          ),
          if (trailingWidth != null) ...[
            const SizedBox(width: KasaSpace.md),
            KasaSkeletonBlock(width: trailingWidth, height: 22, radius: 999),
          ],
        ],
      ),
    );
  }
}

Widget _rowsCard(int count, double? trailingWidth) {
  return _SkeletonSurface(
    child: KasaSkeleton(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            _SkeletonRow(trailingWidth: trailingWidth, index: i),
        ],
      ),
    ),
  );
}

/// Loading state for any list of rows (repairs, notifications, bills, units).
class KasaSkeletonList extends StatelessWidget {
  const KasaSkeletonList({
    super.key,
    this.itemCount = 6,
    this.trailingWidth = 64,
    this.padding = const EdgeInsets.all(KasaSpace.lg),
  });

  final int itemCount;

  /// Width of the trailing block (a status chip, an amount, an input). Null
  /// for rows with nothing on the right.
  final double? trailingWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      child: _rowsCard(itemCount, trailingWidth),
    );
  }
}

/// Loading state for a summary screen: one hero card, then a list.
/// Used by Home, Tax statement and Reports.
class KasaSkeletonSummary extends StatelessWidget {
  const KasaSkeletonSummary({
    super.key,
    this.padding = const EdgeInsets.all(KasaSpace.lg),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonSurface(
            padding: EdgeInsets.all(KasaSpace.lg),
            child: KasaSkeleton(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KasaSkeletonBlock(width: 140, height: 14),
                  SizedBox(height: KasaSpace.md),
                  KasaSkeletonBlock(width: 220, height: 36, radius: 8),
                  SizedBox(height: KasaSpace.sm),
                  KasaSkeletonBlock(width: 160, height: 14),
                  SizedBox(height: KasaSpace.lg),
                  KasaSkeletonBlock(height: 8, radius: 999),
                  SizedBox(height: KasaSpace.xl),
                  Row(
                    children: [
                      Expanded(child: _StatPlaceholder(labelWidth: 60, valueWidth: 110)),
                      SizedBox(width: KasaSpace.lg),
                      Expanded(child: _StatPlaceholder(labelWidth: 70, valueWidth: 80)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KasaSpace.xl),
          const KasaSkeleton(child: KasaSkeletonBlock(width: 130, height: 16)),
          const SizedBox(height: KasaSpace.md),
          _rowsCard(3, null),
        ],
      ),
    );
  }
}

class _StatPlaceholder extends StatelessWidget {
  const _StatPlaceholder({required this.labelWidth, required this.valueWidth});

  final double labelWidth;
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KasaSkeletonBlock(width: labelWidth, height: 12),
        const SizedBox(height: KasaSpace.sm),
        KasaSkeletonBlock(width: valueWidth, height: 22, radius: 8),
      ],
    );
  }
}

/// Loading state for a detail screen (unit, property): identity card with key
/// facts, then a list.
class KasaSkeletonDetail extends StatelessWidget {
  const KasaSkeletonDetail({
    super.key,
    this.padding = const EdgeInsets.all(KasaSpace.lg),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonSurface(
            padding: EdgeInsets.all(KasaSpace.lg),
            child: KasaSkeleton(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      KasaSkeletonBlock(width: 40, height: 40, circle: true),
                      SizedBox(width: KasaSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KasaSkeletonBlock(width: 150, height: 16),
                            SizedBox(height: KasaSpace.sm),
                            KasaSkeletonBlock(width: 110, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: KasaSpace.lg),
                  _FactPlaceholder(valueWidth: 130),
                  _FactPlaceholder(valueWidth: 100),
                  _FactPlaceholder(valueWidth: 70),
                ],
              ),
            ),
          ),
          const SizedBox(height: KasaSpace.xl),
          const KasaSkeleton(child: KasaSkeletonBlock(width: 110, height: 16)),
          const SizedBox(height: KasaSpace.md),
          _rowsCard(3, 56),
        ],
      ),
    );
  }
}

class _FactPlaceholder extends StatelessWidget {
  const _FactPlaceholder({required this.valueWidth});

  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KasaSpace.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const KasaSkeletonBlock(width: 70, height: 13),
          KasaSkeletonBlock(width: valueWidth, height: 14),
        ],
      ),
    );
  }
}
