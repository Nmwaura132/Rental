import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_skeleton.dart';
import '../payments/unplaced_payments.dart';
import '../properties/meter_readings_screen.dart';
import '../properties/properties_screen.dart';
import '../tenants/tenants_screen.dart';

// ─── Needs attention ──────────────────────────────────────────────────────────
//
// The landlord Home's centrepiece: everything that is waiting on the landlord,
// in one list, most urgent first. There is no new endpoint behind it. Each row
// is derived from data the app already loads, and each source loads on its own,
// so one slow or failing source never hides the others.

enum AttentionKind { overdue, unassigned, notice, readings }

/// One property whose metered units still lack a reading for the period.
class MissingReadings {
  const MissingReadings({
    required this.propertyId,
    required this.propertyName,
    required this.missing,
    required this.total,
  });

  final int propertyId;
  final String propertyName;

  /// Occupied metered units with no reading yet, and all occupied metered units.
  final int missing;
  final int total;
}

class AttentionItem {
  const AttentionItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.propertyId,
    this.propertyName,
  });

  final AttentionKind kind;
  final String title;
  final String subtitle;

  // Only for [AttentionKind.readings]: where the row opens.
  final int? propertyId;
  final String? propertyName;
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

/// Turns the raw sources into rows. Pure, so it can be tested without a network.
///
/// Order is by urgency: money already late, money nobody has claimed, people
/// leaving, then routine chores. Caretakers get only the chores: they have no
/// Money tab and no business with arrears or bank payments.
List<AttentionItem> buildAttentionItems({
  required bool canSeeMoney,
  int overdueCount = 0,
  double overdueAmount = 0,
  List<Map<String, dynamic>> unplaced = const [],
  List<Map<String, dynamic>> tenancies = const [],
  List<MissingReadings> missingReadings = const [],
}) {
  final items = <AttentionItem>[];

  if (canSeeMoney && overdueCount > 0) {
    items.add(AttentionItem(
      kind: AttentionKind.overdue,
      title: overdueCount == 1 ? '1 bill overdue' : '$overdueCount bills overdue',
      subtitle: formatCurrency(overdueAmount),
    ));
  }

  if (canSeeMoney && unplaced.isNotEmpty) {
    final total = unplaced.fold<double>(0, (s, r) => s + _num(r['amount']));
    items.add(AttentionItem(
      kind: AttentionKind.unassigned,
      title: unplaced.length == 1
          ? '1 payment to assign'
          : '${unplaced.length} payments to assign',
      subtitle: formatCurrency(total),
    ));
  }

  // Tenancies that are still active and have a notice date set, soonest first.
  final leaving = <({Map<String, dynamic> t, DateTime out})>[];
  for (final t in tenancies) {
    if (t['status'] != 'active') continue;
    final out = DateTime.tryParse(t['notice_effective_date']?.toString() ?? '');
    if (out != null) leaving.add((t: t, out: out));
  }
  leaving.sort((a, b) => a.out.compareTo(b.out));
  if (leaving.isNotEmpty) {
    final first = leaving.first;
    final where = '${first.t['unit_number'] ?? ''}, ${first.t['property_name'] ?? ''}';
    final when = 'leaves ${DateFormat('d MMM').format(first.out)}';
    items.add(AttentionItem(
      kind: AttentionKind.notice,
      title: leaving.length == 1
          ? 'Notice to vacate'
          : '${leaving.length} notices to vacate',
      subtitle: leaving.length == 1
          ? '$where · $when'
          : 'Next: $where · $when',
    ));
  }

  for (final m in missingReadings) {
    if (m.missing <= 0) continue;
    items.add(AttentionItem(
      kind: AttentionKind.readings,
      title: 'Meter readings missing',
      subtitle: '${m.propertyName} · ${m.total - m.missing} of ${m.total} units',
      propertyId: m.propertyId,
      propertyName: m.propertyName,
    ));
  }

  return items;
}

/// Reads one property's sheet into a [MissingReadings], or null when nothing is
/// missing or the sheet cannot be read.
///
/// WHY a failed sheet is dropped rather than shown: this is a nudge. A property
/// with a broken sheet still opens its own readings screen, which reports the
/// error properly; a banner that cried wolf on every network blip would not.
MissingReadings? missingFromSheet(
  int propertyId,
  String propertyName,
  Map<String, dynamic> sheet,
) {
  final rows = (sheet['rows'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final occupied = <dynamic>{};
  final lacking = <dynamic>{};
  for (final r in rows) {
    if (r['occupied'] != true) continue;
    occupied.add(r['unit']);
    if (r['reading'] == null) lacking.add(r['unit']);
  }
  if (lacking.isEmpty) return null;
  return MissingReadings(
    propertyId: propertyId,
    propertyName: propertyName,
    missing: lacking.length,
    total: occupied.length,
  );
}

final missingReadingsProvider =
    FutureProvider.autoDispose<List<MissingReadings>>((ref) async {
  final dio = ref.watch(dioProvider);
  final props = await ref.watch(propertiesProvider.future);
  final period = DateFormat('yyyy-MM-dd').format(defaultReadingPeriod());

  final results = await Future.wait(props.map((p) async {
    final id = p['id'] as int;
    try {
      final res = await dio.get(
        '/api/v1/properties/meter-readings/sheet/',
        queryParameters: {'property': id, 'period': period},
      );
      return missingFromSheet(
        id,
        p['name']?.toString() ?? '',
        Map<String, dynamic>.from(res.data as Map),
      );
    } catch (_) {
      return null;
    }
  }));
  return results.whereType<MissingReadings>().toList();
});

class NeedsAttentionSection extends ConsumerWidget {
  const NeedsAttentionSection({
    super.key,
    required this.canSeeMoney,
    required this.overdueCount,
    required this.overdueAmount,
  });

  final bool canSeeMoney;
  final int overdueCount;
  final double overdueAmount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final unplaced = canSeeMoney ? ref.watch(unplacedPaymentsProvider) : null;
    final tenancies = ref.watch(tenanciesProvider);
    final readings = ref.watch(missingReadingsProvider);

    final sources = <AsyncValue<Object?>>[
      if (unplaced != null) unplaced,
      tenancies,
      readings,
    ];
    final loading = sources.any((s) => s.isLoading && !s.hasValue);
    final failed = sources.any((s) => s.hasError && !s.hasValue);

    final items = buildAttentionItems(
      canSeeMoney: canSeeMoney,
      overdueCount: overdueCount,
      overdueAmount: overdueAmount,
      unplaced: unplaced?.valueOrNull ?? const [],
      tenancies:
          (tenancies.valueOrNull ?? const []).cast<Map<String, dynamic>>(),
      missingReadings: readings.valueOrNull ?? const [],
    );

    void retry() {
      ref.invalidate(unplacedPaymentsProvider);
      ref.invalidate(tenanciesProvider);
      ref.invalidate(missingReadingsProvider);
    }

    return Semantics(
      container: true,
      label: 'Needs attention',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Needs attention',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              if (items.isNotEmpty)
                Text(
                  '${items.length}',
                  style: KasaFont.sans(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: KasaSpace.md),
          if (items.isNotEmpty)
            _AttentionList(items: items)
          else if (loading)
            const KasaSkeletonList(
              itemCount: 2,
              trailingWidth: null,
              padding: EdgeInsets.zero,
            )
          else if (failed)
            _QuietRow(
              icon: Icons.refresh_rounded,
              title: 'Could not check everything',
              subtitle: 'Tap to try again',
              onTap: retry,
            )
          else
            const _QuietRow(
              icon: Icons.check_rounded,
              title: 'All caught up',
              subtitle: 'Nothing is waiting on you',
            ),
          // Some rows are already known while another source is still loading
          // or failed; say so instead of implying the list is complete.
          if (items.isNotEmpty && failed)
            Padding(
              padding: const EdgeInsets.only(top: KasaSpace.sm),
              child: TextButton(
                onPressed: retry,
                child: const Text('Some items could not load. Try again'),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.items});

  final List<AttentionItem> items;

  void _open(BuildContext context, AttentionItem item) {
    switch (item.kind) {
      case AttentionKind.overdue:
        context.go('/invoices');
      case AttentionKind.unassigned:
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const UnplacedPaymentsScreen()),
        );
      case AttentionKind.notice:
        context.push('/tenants');
      case AttentionKind.readings:
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => MeterReadingsScreen(
              propertyId: item.propertyId!,
              propertyName: item.propertyName ?? '',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(KasaRadius.md),
        border: Border.all(color: cs.kasaStroke, width: KasaBorders.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: cs.kasaStroke),
            _AttentionRow(
              item: items[i],
              onTap: () => _open(context, items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Colour carries the kind, but the icon and the words say it too, so nothing
/// depends on telling coral from amber.
({Color fg, Color bg, IconData icon}) _look(ColorScheme cs, AttentionKind k) {
  switch (k) {
    case AttentionKind.overdue:
      return (
        fg: cs.statusOverdue,
        bg: cs.statusOverdueBg,
        icon: Icons.error_outline_rounded,
      );
    case AttentionKind.unassigned:
      return (
        fg: cs.statusDue,
        bg: cs.statusDueBg,
        icon: Icons.account_balance_wallet_outlined,
      );
    case AttentionKind.notice:
      return (
        fg: cs.statusNotice,
        bg: cs.statusNoticeBg,
        icon: Icons.door_front_door_outlined,
      );
    case AttentionKind.readings:
      return (
        fg: cs.onSurface,
        bg: cs.surfaceContainerHighest,
        icon: Icons.speed_rounded,
      );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, required this.onTap});

  final AttentionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final look = _look(cs, item.kind);

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KasaSpace.lg,
            vertical: KasaSpace.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: look.bg,
                  borderRadius: BorderRadius.circular(KasaRadius.sm),
                ),
                child: Icon(look.icon, size: 20, color: look.fg),
              ),
              const SizedBox(width: KasaSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietRow extends StatelessWidget {
  const _QuietRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KasaRadius.md),
        side: BorderSide(color: cs.kasaStroke, width: KasaBorders.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KasaSpace.lg,
              vertical: KasaSpace.md,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: KasaSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: tt.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        subtitle,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
