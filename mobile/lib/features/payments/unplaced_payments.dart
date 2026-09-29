import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/kasa_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_primitives.dart';
import 'invoices_screen.dart';

/// Money that reached the landlord's account but could not be placed against
/// a bill — a mistyped account number, or rent paid before the month's bill
/// was raised. Until it is assigned here, the tenant who paid still looks like
/// they owe it.
final unplacedPaymentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await fetchAllPages(
    ref.watch(dioProvider),
    '/api/v1/payments/bank/notifications/?status=unmatched',
  );
  return rows.cast<Map<String, dynamic>>();
});

/// Shown at the top of the landlord's bills only while something is waiting.
class UnplacedPaymentsBanner extends ConsumerWidget {
  const UnplacedPaymentsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(unplacedPaymentsProvider).valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final total = rows.fold<double>(0, (sum, r) => sum + toDouble(r['amount']));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: KasaCard(
        accent: KasaCardAccent.tertiary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const UnplacedPaymentsScreen()),
        ),
        child: Row(
          children: [
            Icon(Icons.call_split, color: cs.tertiaryInk, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                rows.length == 1
                    ? '1 payment to assign · ${formatCurrency(total)}'
                    : '${rows.length} payments to assign · ${formatCurrency(total)}',
                style: KasaFont.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.tertiaryInk,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: cs.tertiaryInk),
          ],
        ),
      ),
    );
  }
}

class UnplacedPaymentsScreen extends ConsumerWidget {
  const UnplacedPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(unplacedPaymentsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Payments to assign')),
      body: rows.when(
        loading: () => const KasaSkeletonList(),
        error: (e, _) => Center(child: Text(apiError(e))),
        data: (list) => list.isEmpty
            ? Center(
                child: Text(
                  'Every payment has been assigned.',
                  style: KasaFont.sans(color: cs.kasaTextSub),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: list.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Text(
                      'These arrived but could not be matched to a bill. '
                      'Assign each one to the bill it pays.',
                      style: KasaFont.sans(
                          fontSize: 13, color: cs.kasaTextSub),
                    );
                  }
                  return _UnplacedRow(row: list[i - 1]);
                },
              ),
      ),
    );
  }
}

class _UnplacedRow extends ConsumerWidget {
  const _UnplacedRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final when = DateTime.tryParse(row['credited_at']?.toString() ?? '');
    final ref0 = (row['payment_ref'] as String?)?.trim() ?? '';

    return KasaCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _assign(context, ref),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCurrency(toDouble(row['amount'])),
                  style: KasaFont.sans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    fontFeatures: kTabularFigures,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Account: ${ref0.isEmpty ? '(none entered)' : ref0}',
                  style: KasaFont.mono(
                      fontSize: 11, color: cs.onSurface),
                ),
                Text(
                  [
                    if ((row['payer_name'] as String?)?.isNotEmpty ?? false)
                      row['payer_name'],
                    if ((row['payer_account'] as String?)?.isNotEmpty ?? false)
                      row['payer_account'],
                    if (when != null)
                      DateFormat('d MMM, HH:mm').format(when.toLocal()),
                  ].join(' · '),
                  style: KasaFont.sans(fontSize: 11, color: cs.kasaTextSub),
                ),
                Text(
                  '${row['bank_display'] ?? ''} ${row['transaction_ref'] ?? ''}',
                  style: KasaFont.mono(
                      fontSize: 10, color: cs.kasaTextSub),
                ),
              ],
            ),
          ),
          Text(
            'Assign',
            style: KasaFont.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    const open = {'pending', 'overdue', 'partially_paid'};
    final invoices = (await ref.read(invoicesProvider.future))
        .cast<Map<String, dynamic>>()
        .where((i) => open.contains(i['status']))
        .toList();
    if (!context.mounted) return;

    final invoiceId = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: invoices.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'There are no open bills to assign this to. Raise the '
                    "tenant's bill first, then come back.",
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text('Which bill does this pay?',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    for (final inv in invoices)
                      ListTile(
                        title: Text(
                            '${inv['tenant_name']} · Unit ${inv['unit_number']}'),
                        subtitle: Text(
                            '${inv['invoice_number']} · owes ${formatCurrency(toDouble(inv['balance']))}'),
                        onTap: () => Navigator.pop(ctx, inv['id'] as int),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (invoiceId == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(dioProvider).post(
        '/api/v1/payments/bank/notifications/${row['id']}/match/',
        data: {'invoice_id': invoiceId},
      );
      ref.invalidate(unplacedPaymentsProvider);
      ref.invalidate(invoicesProvider);
      messenger.showSnackBar(const SnackBar(
        content: Text('Payment assigned.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(apiError(e)),
        backgroundColor: errorColor,
      ));
    }
  }
}
