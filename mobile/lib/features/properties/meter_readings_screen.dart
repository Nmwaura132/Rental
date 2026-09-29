import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/kasa_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_primitives.dart';

final _apiDate = DateFormat('yyyy-MM-dd');

/// Readings close a month and are billed on the next month's bill. Late in the
/// month the reading being taken is this month's; early on, it is most likely
/// last month's that was missed.
DateTime defaultReadingPeriod() {
  final now = DateTime.now();
  return now.day >= 20
      ? DateTime(now.year, now.month)
      : DateTime(now.year, now.month - 1);
}

final _sheetProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, (int, DateTime)>((ref, key) async {
  final (propertyId, period) = key;
  final res = await ref.watch(dioProvider).get(
    '/api/v1/properties/meter-readings/sheet/',
    queryParameters: {'property': propertyId, 'period': _apiDate.format(period)},
  );
  return Map<String, dynamic>.from(res.data);
});

class MeterReadingsScreen extends ConsumerStatefulWidget {
  const MeterReadingsScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
  });

  final int propertyId;
  final String propertyName;

  @override
  ConsumerState<MeterReadingsScreen> createState() => _MeterReadingsScreenState();
}

class _MeterReadingsScreenState extends ConsumerState<MeterReadingsScreen> {
  DateTime _period = defaultReadingPeriod();
  // Keyed "unitId:chargeId" so a property metering water and electricity keeps
  // both figures for a unit apart.
  final _controllers = <String, TextEditingController>{};
  final _errors = <String, String>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Map<String, dynamic> row) {
    final key = '${row['unit']}:${row['charge']}';
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: row['reading']?.toString() ?? ''),
    );
  }

  void _changePeriod(DateTime period) {
    for (final c in _controllers.values) {
      c.dispose();
    }
    setState(() {
      _controllers.clear();
      _errors.clear();
      _period = period;
    });
  }

  Future<void> _save(List<Map<String, dynamic>> rows) async {
    setState(() {
      _saving = true;
      _errors.clear();
    });
    final dio = ref.read(dioProvider);
    var saved = 0;

    for (final row in rows) {
      final key = '${row['unit']}:${row['charge']}';
      final text = _controllers[key]?.text.trim() ?? '';
      if (text.isEmpty || text == row['reading']?.toString()) continue;

      try {
        if (row['reading_id'] == null) {
          await dio.post('/api/v1/properties/meter-readings/', data: {
            'unit': row['unit'],
            'charge': row['charge'],
            'period': _apiDate.format(_period),
            'reading': text,
          });
        } else {
          await dio.patch(
            '/api/v1/properties/meter-readings/${row['reading_id']}/',
            data: {'reading': text},
          );
        }
        saved++;
      } catch (e) {
        _errors[key] = apiError(e);
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ref.invalidate(_sheetProvider((widget.propertyId, _period)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_errors.isEmpty
          ? 'Saved $saved ${saved == 1 ? 'reading' : 'readings'}.'
          : '${_errors.length} could not be saved — see the units marked in red.'),
      backgroundColor: _errors.isEmpty ? Colors.green : Theme.of(context).colorScheme.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sheet = ref.watch(_sheetProvider((widget.propertyId, _period)));
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month);
    final lastMonth = DateTime(thisMonth.year, thisMonth.month - 1);

    return Scaffold(
      appBar: AppBar(title: Text('Meter readings · ${widget.propertyName}')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final month in [lastMonth, thisMonth])
                  GestureDetector(
                    onTap: () => _changePeriod(month),
                    child: KasaChip(
                      label: DateFormat('MMMM').format(month),
                      variant: month == _period
                          ? KasaChipVariant.secondary
                          : KasaChipVariant.neutral,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Readings for ${DateFormat('MMMM').format(_period)} are billed on the '
              '${DateFormat('MMMM').format(DateTime(_period.year, _period.month + 1))} bill.',
              style: KasaFont.sans(fontSize: 12, color: cs.kasaTextSub),
            ),
          ),
          Expanded(
            child: sheet.when(
              loading: () => const KasaSkeletonList(trailingWidth: 108),
              error: (e, _) => Center(child: Text(apiError(e))),
              data: (data) {
                final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'This property has no metered charges. Add a metered '
                      'charge such as water to the property first.',
                      style: KasaFont.sans(color: cs.kasaTextSub),
                    ),
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _ReadingRow(
                          row: rows[i],
                          controller: _controllerFor(rows[i]),
                          error: _errors['${rows[i]['unit']}:${rows[i]['charge']}'],
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: KasaButton(
                          label: 'Save readings',
                          variant: KasaButtonVariant.primary,
                          isLoading: _saving,
                          onTap: _saving ? null : () => _save(rows),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.row,
    required this.controller,
    required this.error,
    required this.onChanged,
  });

  final Map<String, dynamic> row;
  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final previous = double.tryParse(row['previous_reading']?.toString() ?? '');
    final current = double.tryParse(controller.text);
    final price = toDouble(row['unit_price']);
    final used = (previous != null && current != null) ? current - previous : null;
    final occupied = row['occupied'] == true;

    return KasaCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unit ${row['unit_number']} · ${row['charge_name']}',
                  style: KasaFont.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: occupied ? cs.onSurface : cs.kasaTextSub,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    previous == null
                        ? 'First reading — sets the starting point'
                        : 'Last: ${NumberFormat('#,##0.##').format(previous)}',
                    if (!occupied) 'vacant',
                  ].join(' · '),
                  style: KasaFont.sans(fontSize: 12, color: cs.kasaTextSub),
                ),
                if (used != null && used >= 0)
                  Text(
                    '${NumberFormat('#,##0.##').format(used)} units · ${formatCurrency(used * price)}',
                    style: KasaFont.mono(fontSize: 11, color: cs.onSurface),
                  ),
                if (used != null && used < 0)
                  Text(
                    'Lower than last month — check the meter',
                    style: KasaFont.sans(fontSize: 11, color: cs.error),
                  ),
                if (error != null)
                  Text(error!, style: KasaFont.sans(fontSize: 11, color: cs.error)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              textAlign: TextAlign.end,
              textInputAction: TextInputAction.next,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Reading',
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
