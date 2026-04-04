import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/utils/api_error.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _propertiesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/properties/properties/');
  final data = resp.data;
  if (data is List) return List<Map<String, dynamic>>.from(data);
  if (data is Map && data['results'] is List) {
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }
  return [];
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  Map<String, dynamic>? _selectedProperty;

  // State per report card: null = idle, 'loading' = generating, URL = done
  final Map<String, String?> _results = {
    'pnl': null,
    'aged': null,
    'ledger': null,
    'rent_roll': null,
  };
  final Map<String, bool> _loading = {
    'pnl': false,
    'aged': false,
    'ledger': false,
    'rent_roll': false,
  };

  // P&L / Ledger date params
  int _pnlYear = DateTime.now().year;
  int _pnlMonth = DateTime.now().month;
  DateTime _ledgerFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _ledgerTo = DateTime.now();

  Future<void> _generate(String type) async {
    final prop = _selectedProperty;
    if (prop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a property first.')),
      );
      return;
    }
    setState(() => _loading[type] = true);
    try {
      final dio = ref.read(dioProvider);
      final params = <String, dynamic>{'type': type, 'property': prop['id']};
      if (type == 'pnl') {
        params['year'] = _pnlYear.toString();
        params['month'] = _pnlMonth.toString();
      }
      if (type == 'ledger') {
        // For ledger, use the first active lease of the property (landlord context)
        // endpoint accepts `property` param; we pass date range
        params['date_from'] = DateFormat('yyyy-MM-dd').format(_ledgerFrom);
        params['date_to'] = DateFormat('yyyy-MM-dd').format(_ledgerTo);
      }
      final resp = await dio.get('/api/v1/payments/reports/', queryParameters: params);
      final url = resp.data['pdf_url'] as String? ?? '';
      setState(() => _results[type] = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading[type] = false);
    }
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PDF URL copied to clipboard. Open in your browser.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final propsAsync = ref.watch(_propertiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Financial Reports')),
      body: propsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiError(e))),
        data: (props) {
          if (props.isEmpty) {
            return const Center(
              child: Text('No properties found.'),
            );
          }

          _selectedProperty ??= props.first;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Property picker
              const _SectionLabel('Property'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Map<String, dynamic>>(
                      isExpanded: true,
                      value: _selectedProperty,
                      items: props
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p['name'] as String? ?? '—'),
                              ))
                          .toList(),
                      onChanged: (p) => setState(() {
                        _selectedProperty = p;
                        // Clear stale results on property change
                        for (final k in _results.keys) {
                          _results[k] = null;
                        }
                      }),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const _SectionLabel('Reports'),

              // P&L
              _ReportCard(
                icon: Icons.bar_chart,
                title: 'Monthly P&L',
                subtitle: 'Rent collection vs expected for a month. Includes KRA RRIT line.',
                color: Colors.blue,
                loading: _loading['pnl']!,
                resultUrl: _results['pnl'],
                onGenerate: () => _generate('pnl'),
                onCopy: _copyUrl,
                extra: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _YearMonthPicker(
                          label: 'Year',
                          value: _pnlYear,
                          items: List.generate(5, (i) => DateTime.now().year - i),
                          onChanged: (v) => setState(() => _pnlYear = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _YearMonthPicker(
                          label: 'Month',
                          value: _pnlMonth,
                          items: List.generate(12, (i) => i + 1),
                          itemLabel: (v) => DateFormat('MMMM').format(DateTime(2000, v)),
                          onChanged: (v) => setState(() => _pnlMonth = v),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Aged Receivables
              _ReportCard(
                icon: Icons.warning_amber_outlined,
                title: 'Aged Receivables',
                subtitle: 'Who owes what, bucketed by days overdue. Useful for follow-ups.',
                color: Colors.orange,
                loading: _loading['aged']!,
                resultUrl: _results['aged'],
                onGenerate: () => _generate('aged'),
                onCopy: _copyUrl,
              ),

              const SizedBox(height: 12),

              // Tenant Ledger
              _ReportCard(
                icon: Icons.receipt_long_outlined,
                title: 'Tenant Ledger',
                subtitle: 'Chronological debits and credits for a property over a date range.',
                color: Colors.purple,
                loading: _loading['ledger']!,
                resultUrl: _results['ledger'],
                onGenerate: () => _generate('ledger'),
                onCopy: _copyUrl,
                extra: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _DatePickerTile(
                          label: 'From',
                          value: _ledgerFrom,
                          onChanged: (d) => setState(() => _ledgerFrom = d),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DatePickerTile(
                          label: 'To',
                          value: _ledgerTo,
                          onChanged: (d) => setState(() => _ledgerTo = d),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Rent Roll
              _ReportCard(
                icon: Icons.apartment_outlined,
                title: 'Rent Roll',
                subtitle: 'All units with tenant, rent, last payment, and arrears.',
                color: Colors.teal,
                loading: _loading['rent_roll']!,
                resultUrl: _results['rent_roll'],
                onGenerate: () => _generate('rent_roll'),
                onCopy: _copyUrl,
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );
}

// ─── Report Card ─────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.loading,
    required this.resultUrl,
    required this.onGenerate,
    required this.onCopy,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool loading;
  final String? resultUrl;
  final VoidCallback onGenerate;
  final void Function(String) onCopy;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
            if (extra != null) extra!,
            const SizedBox(height: 12),
            if (resultUrl != null && resultUrl!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PDF ready',
                        style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => onCopy(resultUrl!),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy URL'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green.shade800,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: loading ? null : onGenerate,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(loading
                    ? 'Generating…'
                    : resultUrl != null
                        ? 'Regenerate'
                        : 'Generate PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Year/Month picker ────────────────────────────────────────────────────────

class _YearMonthPicker extends StatelessWidget {
  const _YearMonthPicker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabel,
  });

  final String label;
  final int value;
  final List<int> items;
  final void Function(int) onChanged;
  final String Function(int)? itemLabel;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: items
          .map((v) => DropdownMenuItem(
                value: v,
                child: Text(itemLabel != null ? itemLabel!(v) : '$v'),
              ))
          .toList(),
      onChanged: (v) => v != null ? onChanged(v) : null,
    );
  }
}

// ─── Date picker tile ─────────────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final void Function(DateTime) onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        ),
        child: Text(
          DateFormat('d MMM yyyy').format(value),
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
