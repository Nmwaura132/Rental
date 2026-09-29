import 'package:flutter/material.dart';

import '../../core/widgets/kasa_skeleton.dart';

/// Legacy entry point kept so existing screens compile unchanged.
///
/// It now delegates to [KasaSkeletonList], so every list screen shares one
/// skeleton look, one shimmer, and the reduced-motion handling. New code should
/// use [KasaSkeletonList] directly.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(12),
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return KasaSkeletonList(itemCount: itemCount, padding: padding);
  }
}
