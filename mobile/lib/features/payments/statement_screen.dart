import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';

const _url = '/api/v1/payments/reports/';

final _buildingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await fetchAllPages(ref.watch(dioProvider), '/api/v1/properties/');
  return rows.cast<Map<String, dynamic>>();
});

typedef _Statement = ({List<Map<String, dynamic>> months, List<Map<String, dynamic>> deposits});

final _statementProvider = FutureProvider.autoDispose.family<_Statement, int>((ref, buildingId) async {
  final res = await ref.watch(dioProvider).get(_url, queryParameters: {'type': 'statement', 'property': buildingId});
  return (
    months: (res.data['months'] as List).cast<Map<String, dynamic>>(),
    deposits: (res.data['deposits'] as List).cast<Map<String, dynamic>>(),
  );
});

final _figures = NumberFormat('#,##0.##');

/// 25000 -> "25,000"; 12.5 -> "12.5".
String _n(Object? v) => _figures.format(toDouble(v));

String _houses(int n) => n == 1 ? '1 house' : '$n houses';

/// Every month's bills for a building, house by house: rent, water and
/// service charge paid, the water readings behind each charge, and the
/// deposits held. The same figures download as an Excel file.
class StatementScreen extends ConsumerStatefulWidget {
  const StatementScreen({super.key});

  @override
  ConsumerState<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends ConsumerState<StatementScreen> {
  int? _buildingId;
  String? _month;
  bool _downloading = false;

  Future<void> _download(int buildingId) async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref.read(dioProvider).get(_url, queryParameters: {
        'type': 'statement',
        'property': buildingId,
        'download': 'xlsx',
        if (_month != null) 'month': _month,
      });
      final link = res.data['file_url'] as String;
      var opened = false;
      try {
        opened = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: link));
        messenger.showSnackBar(const SnackBar(content: Text('Could not open a browser. The link is copied.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiError(e))));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildings = ref.watch(_buildingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Statement')),
      body: buildings.when(
        loading: () => const KasaSkeletonSummary(),
        error: (e, _) => Center(child: Text(apiError(e))),
        data: (all) {
          if (all.isEmpty) return const Center(child: Text('Add a building to see its statement.'));
          final id = all.any((b) => b['id'] == _buildingId) ? _buildingId! : all.first['id'] as int;
          final statement = ref.watch(_statementProvider(id));
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(_statementProvider(id).future),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                  if (all.length > 1) ...[
                    _Pills(
                      options: [for (final b in all) (b['id'] as int, '${b['name']}')],
                      selected: id,
                      onPick: (v) => setState(() {
                        _buildingId = v;
                        _month = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ...statement.when(
                    loading: () => [const KasaSkeletonSummary()],
                    error: (e, _) => [Text(apiError(e))],
                    data: (s) => _body(context, s),
                  ),
                ]),
              ),
            ),
            if (statement.valueOrNull?.months.isNotEmpty ?? false)
              KasaActionBar(children: [
                KasaButton(
                  label: _month == null ? 'Download Excel' : 'Download this month',
                  leading: const Icon(Icons.download_rounded, size: 20),
                  isLoading: _downloading,
                  onTap: _downloading ? null : () => _download(id),
                ),
              ]),
          ]);
        },
      ),
    );
  }

  List<Widget> _body(BuildContext context, _Statement statement) {
    final months = statement.months;
    if (months.isEmpty) {
      return [
        const KasaNotice(
          icon: Icons.receipt_long_outlined,
          title: 'No bills yet',
          body: 'Each month appears here once its bills are made.',
        ),
      ];
    }
    final newestFirst = months.reversed.toList();
    final shown = _month == null ? newestFirst : newestFirst.where((m) => m['month'] == _month).toList();
    return [
      _Pills<String?>(
        options: [(null, 'All months'), for (final m in newestFirst) (m['month'] as String, '${m['label']}')],
        selected: _month,
        onPick: (v) => setState(() => _month = v),
      ),
      const SizedBox(height: 16),
      _Summary(months: shown),
      for (final month in shown) ...[
        const SizedBox(height: 24),
        KasaSectionHeader('${month['label']}',
            trailing: Text(_houses((month['rows'] as List).length),
                style: KasaFont.sans(fontSize: 13, color: Theme.of(context).colorScheme.kasaTextSub))),
        const SizedBox(height: 8),
        KasaListGroup(children: [
          for (final row in (month['rows'] as List).cast<Map<String, dynamic>>()) _HouseRow(row),
        ]),
      ],
      if (_month == null && statement.deposits.isNotEmpty) ...[
        const SizedBox(height: 24),
        _Deposits(statement.deposits),
      ],
    ];
  }
}

/// Every tenant's deposit and what became of it.
class _Deposits extends StatelessWidget {
  const _Deposits(this.deposits);
  final List<Map<String, dynamic>> deposits;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final figure = KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)
        .copyWith(fontFeatures: kTabularFigures);
    final held = deposits.fold(0.0, (t, d) => t + toDouble(d['held']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KasaSectionHeader('Deposits',
          trailing: Text('${formatCurrency(held)} held', style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub))),
      const SizedBox(height: 8),
      KasaListGroup(children: [
        for (final d in deposits)
          KasaListRow(
            tight: true,
            title: '${d['unit']} · ${d['tenant']}',
            subtitle: d['moved_in'] == null
                ? '${d['status']}'
                : '${d['status']} · moved in ${DateFormat('d MMM yyyy').format(DateTime.parse('${d['moved_in']}'))}',
            trailing: Text(_n(d['amount']), style: figure),
          ),
      ]),
    ]);
  }
}

class _Pills<T> extends StatelessWidget {
  const _Pills({required this.options, required this.selected, required this.onPick});
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (value, label) in options) ...[
            KasaFilterPill(label: label, selected: value == selected, onTap: () => onPick(value)),
            const SizedBox(width: 8),
          ],
        ]),
      );
}

/// Totals for what is on screen: one month, or all of them.
class _Summary extends StatelessWidget {
  const _Summary({required this.months});
  final List<Map<String, dynamic>> months;

  double _sum(String key) => months.fold(0.0, (t, m) => t + toDouble((m['totals'] as Map)[key]));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final figure = KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)
        .copyWith(fontFeatures: kTabularFigures);
    Widget line(String label, String key, {bool strong = false}) =>
        KasaKeyValue(label, Text(formatCurrency(_sum(key)), style: figure), strong: strong);
    final owed = _sum('balance');
    return KasaCard(
      child: Column(children: [
        line('Billed', 'billed'),
        line('Paid on bills', 'paid'),
        KasaKeyValue('Still owed',
            Text(formatCurrency(owed), style: figure.copyWith(color: owed > 0 ? cs.statusPair(KasaStatusKind.overdue).fg : null))),
        Divider(height: 16, color: cs.kasaStroke),
        line('Rent paid', 'rent_paid'),
        line('Water paid', 'water_paid'),
        line('Service charge paid', 'service_paid'),
        if (_sum('other_paid') > 0) line('Other paid', 'other_paid'),
        if (_sum('deposit_paid') > 0) line('Deposits received', 'deposit_paid'),
        KasaKeyValue('Water used', Text('${_n(_sum('water_units'))} units', style: figure)),
        Divider(height: 16, color: cs.kasaStroke),
        line('Total received', 'received', strong: true),
      ]),
    );
  }
}

class _HouseRow extends StatelessWidget {
  const _HouseRow(this.row);
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = KasaFont.sans(fontSize: 13, color: cs.kasaTextSub).copyWith(fontFeatures: kTabularFigures);
    final owed = toDouble(row['balance']);
    final hasReading = row['water_current'] != null;
    final water = toDouble(row['water_billed']) > 0 || hasReading;
    final other = toDouble(row['other_billed']) > 0;
    final deposit = toDouble(row['deposit_paid']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('${row['unit']} · ${row['tenant']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KasaFont.sans(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ),
          const SizedBox(width: 8),
          KasaStatusChip(
            kind: owed > 0 ? KasaStatusKind.overdue : KasaStatusKind.paid,
            label: owed > 0 ? 'Owes ${_n(owed)}' : 'Paid',
          ),
        ]),
        const SizedBox(height: 6),
        Text('Rent ${_n(row['rent_paid'])} · Service ${_n(row['service_paid'])}'
            '${other ? ' · Other ${_n(row['other_paid'])}' : ''}', style: sub),
        if (water)
          Text(
            hasReading
                ? 'Water ${_n(row['water_previous'])} → ${_n(row['water_current'])}: '
                    '${_n(row['water_units'])} units × ${_n(row['water_price'])} = ${_n(row['water_billed'])}'
                : 'Water ${_n(row['water_billed'])}',
            style: sub,
          ),
        if (deposit > 0) Text('Deposit ${_n(deposit)} paid on moving in', style: sub),
        const SizedBox(height: 4),
        Text(
          'Paid ${_n(row['paid'])} of ${_n(row['billed'])}'
          '${'${row['paid_via']}'.isEmpty ? '' : ' · ${row['paid_via']}'}',
          style: sub.copyWith(color: cs.onSurface),
        ),
      ]),
    );
  }
}
