import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_primitives.dart';

/// The month the statement is showing, as (year, month).
final taxPeriodProvider = StateProvider.autoDispose<DateTime>(
  (ref) => DateTime(DateTime.now().year, DateTime.now().month),
);

final mriStatementProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final period = ref.watch(taxPeriodProvider);
  final dio = ref.watch(dioProvider);
  final resp = await dio.get(
    '/api/v1/payments/mri/',
    queryParameters: {'year': period.year, 'month': period.month},
  );
  return resp.data as Map<String, dynamic>;
});

/// Monthly Rental Income statement — what the landlord owes KRA and what they
/// need in hand to file it.
///
/// WHY this screen exists rather than a number on the dashboard: MRI is filed
/// per month by the 20th of the next month, on rent RECEIVED, and eRITS wants a
/// rent roll carrying each tenant's KRA PIN. All of that is a working document,
/// not a statistic.
class TaxScreen extends ConsumerWidget {
  const TaxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final period = ref.watch(taxPeriodProvider);
    final statement = ref.watch(mriStatementProvider);

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        backgroundColor: cs.kasaBg,
        title: Text(
          'RENTAL INCOME TAX',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.04,
            color: cs.onSurface,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MonthPicker(
              period: period,
              onChange: (d) => ref.read(taxPeriodProvider.notifier).state = d,
            ),
            Expanded(
              child: statement.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined,
                            size: 56, color: cs.kasaTextSub),
                        const SizedBox(height: 12),
                        Text(apiError(e),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: cs.kasaTextSub)),
                        const SizedBox(height: 16),
                        KasaButton(
                          label: 'RETRY',
                          variant: KasaButtonVariant.secondary,
                          onTap: () => ref.invalidate(mriStatementProvider),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (d) => _Statement(data: d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({required this.period, required this.onChange});
  final DateTime period;
  final ValueChanged<DateTime> onChange;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month);
    // Rent for a future month cannot have been received yet, so there is
    // nothing to file and no reason to let them page forward into it.
    final canGoForward = period.isBefore(thisMonth);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: () =>
                onChange(DateTime(period.year, period.month - 1)),
          ),
          Expanded(
            child: Text(
              DateFormat('MMMM yyyy').format(period).toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: canGoForward
                ? () => onChange(DateTime(period.year, period.month + 1))
                : null,
          ),
        ],
      ),
    );
  }
}

class _Statement extends StatelessWidget {
  const _Statement({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gross = toDouble(data['gross_rent_received']);
    final taxDue = toDouble(data['tax_due']);
    final rate = toDouble(data['tax_rate']);
    final rows = (data['rent_roll'] as List? ?? []).cast<Map<String, dynamic>>();
    final missing =
        (data['tenants_missing_kra_pin'] as List? ?? []).cast<String>();
    final due = data['filing_due_date']?.toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        KasaCard(
          accent: KasaCardAccent.primary,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TAX DUE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.04,
                    color: cs.onPrimary.withValues(alpha: 0.75),
                  )),
              const SizedBox(height: 8),
              Text(
                formatCurrency(taxDue),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  color: cs.onPrimary,
                  height: 1,
                  fontFeatures: kTabularFigures,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${(rate * 100).toStringAsFixed(1)}% of ${formatCurrency(gross)} received',
                style: GoogleFonts.inter(
                    fontSize: 13, color: cs.onPrimary.withValues(alpha: 0.9)),
              ),
              if (due != null) ...[
                const SizedBox(height: 4),
                Text(
                  'File and pay by ${_pretty(due)}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // A nil month still has to be filed; silence here would read as
        // "nothing to do" when KRA expects a return either way.
        if (gross == 0)
          const _Note(
            icon: Icons.info_outline,
            text: 'No rent received this month. KRA still expects a NIL return '
                'by the deadline above.',
          ),

        if (missing.isNotEmpty) ...[
          if (gross == 0) const SizedBox(height: 10),
          _Note(
            icon: Icons.warning_amber_rounded,
            tone: cs.error,
            text: missing.length == 1
                ? '${missing.first} has no KRA PIN on file. eRITS needs it to '
                    'accept this filing.'
                : '${missing.length} tenants have no KRA PIN on file. eRITS '
                    'needs them to accept this filing.',
          ),
        ],

        const SizedBox(height: 20),
        Text('RENT ROLL',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04,
              color: cs.kasaTextSub,
            )),
        const SizedBox(height: 8),

        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No rent received in this month.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: cs.kasaTextSub),
            ),
          )
        else
          ...rows.map((r) => _RentRollRow(row: r)),
      ],
    );
  }

  static String _pretty(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('d MMMM yyyy').format(d);
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.tone});
  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = tone ?? cs.onSurfaceVariant;
    return KasaCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

class _RentRollRow extends StatelessWidget {
  const _RentRollRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pin = (row['tenant_kra_pin'] as String? ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KasaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row['tenant']?.toString() ?? 'Unknown',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Text(
                  formatCurrency(toDouble(row['rent_received'])),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${row['property'] ?? ''} · Unit ${row['unit'] ?? ''}',
              style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  pin.isEmpty ? Icons.error_outline : Icons.verified_outlined,
                  size: 14,
                  color: pin.isEmpty ? cs.error : cs.kasaTextSub,
                ),
                const SizedBox(width: 6),
                Text(
                  pin.isEmpty ? 'KRA PIN missing' : pin,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: pin.isEmpty ? cs.error : cs.kasaTextSub,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
