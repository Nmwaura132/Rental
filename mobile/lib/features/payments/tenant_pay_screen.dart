import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../dashboard/dashboard_screen.dart';
import 'invoices_screen.dart';

/// The tenant's Pay tab: the bill to pay now, then every payment they have
/// made, newest first.
class TenantPayScreen extends ConsumerWidget {
  const TenantPayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final home = ref.watch(dashboardProvider);
    final payments = ref.watch(paymentsReceivedProvider);
    final bills = ref.watch(invoicesProvider);

    Future<void> refresh() async {
      ref.invalidate(paymentsReceivedProvider);
      ref.invalidate(invoicesProvider);
      ref.invalidate(dashboardProvider);
      await ref.read(dashboardProvider.future);
    }

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Text('Pay', style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            home.when(
              loading: () => const SizedBox(height: 96),
              error: (e, _) => KasaNotice(icon: Icons.cloud_off_outlined, title: apiError(e)),
              data: (data) => _CurrentBill(data: data, bills: bills.valueOrNull),
            ),
            const SizedBox(height: 24),
            KasaSectionHeader('History',
                trailing: Text('Newest first', style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub))),
            const SizedBox(height: 12),
            payments.when(
              loading: () => const SkeletonList(),
              error: (e, _) => KasaNotice(icon: Icons.cloud_off_outlined, title: apiError(e)),
              data: (rows) => rows.isEmpty
                  ? Text('No payments yet.', style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub))
                  : KasaListGroup(children: [for (final p in rows) _PaymentRow(payment: p)]),
            ),
            const SizedBox(height: 16),
            if (toDouble(home.valueOrNull?['deposit_held']) > 0)
              Text(
                'Deposit held by your landlord: ${formatCurrency(toDouble(home.valueOrNull?['deposit_held']))}.',
                style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub),
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrentBill extends ConsumerWidget {
  const _CurrentBill({required this.data, required this.bills});
  final Map<String, dynamic> data;
  final List<dynamic>? bills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final bill = (data['current_bill'] as Map?)?.cast<String, dynamic>();
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);

    if (bill == null) {
      return KasaCard(
        child: Row(children: [
          Expanded(child: Text('Nothing to pay right now.', style: muted)),
          const KasaStatusChip(kind: KasaStatusKind.paid, label: 'Paid up'),
        ]),
      );
    }

    final overdue = bill['status'] == 'overdue';
    final due = DateFormat('d MMM').format(DateTime.parse('${bill['due_date']}'));
    final month = DateFormat('MMMM').format(DateTime.parse('${bill['period_start']}'));
    // The full bill (items, payments) comes from the bills list; open it when
    // it is there.
    Map<String, dynamic>? full;
    for (final b in bills ?? const []) {
      if (b is Map && b['id'] == bill['id']) full = Map<String, dynamic>.from(b);
    }

    return KasaCard(
      onTap: full == null ? null : () => openBill(context, ref, full!),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$month bill · due $due', style: muted),
            const SizedBox(height: 6),
            Text(formatCurrency(toDouble(bill['balance'])), style: KasaType.moneyL.copyWith(color: cs.onSurface)),
          ]),
        ),
        const SizedBox(width: 8),
        KasaStatusChip(kind: overdue ? KasaStatusKind.overdue : KasaStatusKind.due, label: overdue ? 'Overdue' : 'Due'),
      ]),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});
  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = payment;
    final month = p['period_start'] == null ? 'Payment' : DateFormat('MMMM yyyy').format(DateTime.parse('${p['period_start']}'));
    final when = p['paid_at'] == null ? '' : DateFormat('d MMM').format(DateTime.parse('${p['paid_at']}').toLocal());
    final how = switch (p['method']) {
      'mpesa' => 'M-Pesa ${p['mpesa_receipt_number'] ?? ''}'.trim(),
      'cash' => 'Cash · recorded by landlord',
      'deposit' => 'From your deposit',
      _ => '${p['method_display'] ?? p['method']}',
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(month, style: KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text([when, how].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: KasaFont.mono(fontSize: 12, color: cs.kasaTextSub)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(formatCurrency(toDouble(p['amount'])),
              style: KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)
                  .copyWith(fontFeatures: KasaType.tabular)),
        ]),
      ),
    );
  }
}
