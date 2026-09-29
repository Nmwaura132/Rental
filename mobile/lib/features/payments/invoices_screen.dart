import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/kasa_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/constants.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../shared/widgets/shimmer_loading.dart';
import 'unplaced_payments.dart';

final _apiDate = DateFormat('yyyy-MM-dd');
final _displayDate = DateFormat('dd MMM yyyy');

final invoicesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  return fetchAllPages(dio, '/api/v1/payments/invoices/');
});

// ─── Line Item Entry (mutable state for one invoice line item) ────────────────

class _LineItemEntry {
  final String chargeType;
  final String description;
  final bool isMetered;
  final double? unitPrice;
  bool enabled = true;

  final TextEditingController amountCtrl; // flat charges and rent
  final TextEditingController prevCtrl; // metered: previous meter reading
  final TextEditingController currCtrl; // metered: current meter reading

  _LineItemEntry({
    required this.chargeType,
    required this.description,
    required this.isMetered,
    this.unitPrice,
    double initialAmount = 0,
  })  : amountCtrl = TextEditingController(
            text: initialAmount > 0 ? initialAmount.toStringAsFixed(0) : ''),
        prevCtrl = TextEditingController(),
        currCtrl = TextEditingController();

  double get computedAmount {
    if (isMetered) {
      final prev = double.tryParse(prevCtrl.text) ?? 0;
      final curr = double.tryParse(currCtrl.text) ?? 0;
      final units = (curr - prev).clamp(0.0, double.infinity);
      return units * (unitPrice ?? 0);
    }
    return double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
  }

  Map<String, dynamic> toMap() {
    if (isMetered) {
      final prev = double.tryParse(prevCtrl.text) ?? 0;
      final curr = double.tryParse(currCtrl.text) ?? 0;
      final units = (curr - prev).clamp(0.0, double.infinity);
      return {
        'description': description,
        'charge_type': chargeType,
        'previous_reading': prev,
        'current_reading': curr,
        'units_consumed': units,
        'unit_price': unitPrice,
        'amount': computedAmount,
      };
    }
    return {
      'description': description,
      'charge_type': chargeType,
      'amount': computedAmount,
    };
  }

  void dispose() {
    amountCtrl.dispose();
    prevCtrl.dispose();
    currCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Every confirmed payment the viewer may see, newest first.
final paymentsReceivedProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await fetchAllPages(ref.watch(dioProvider), '/api/v1/payments/?status=confirmed');
  return rows.cast<Map<String, dynamic>>();
});

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  String _filter = 'all';
  bool _showPayments = false;

  static const _due = {'pending', 'partially_paid'};

  bool _matches(Map<String, dynamic> bill) => switch (_filter) {
        'overdue' => bill['status'] == 'overdue',
        'due' => _due.contains(bill['status']),
        'paid' => bill['status'] == 'paid',
        _ => true,
      };

  Future<void> _refresh() {
    ref.invalidate(unplacedPaymentsProvider);
    ref.invalidate(paymentsReceivedProvider);
    return ref.refresh(invoicesProvider.future);
  }

  void _newBill() => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            appBar: AppBar(
              title: const Text('New bill'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: _CreateInvoiceDialog(onDone: () => ref.invalidate(invoicesProvider)),
          ),
        ),
      );

  Future<void> _recordPayment() async {
    final id = await pickOpenBill(context, ref, title: 'Which bill is this payment for?');
    if (id == null || !mounted) return;
    final bill = (await ref.read(invoicesProvider.future))
        .cast<Map<String, dynamic>>()
        .firstWhere((b) => b['id'] == id);
    if (!mounted) return;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _RecordPaymentDialog(
        invoiceId: id,
        balance: toDouble(bill['balance']),
        onDone: () => ref.invalidate(invoicesProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoicesProvider);
    final isLandlord = ref.watch(userRoleProvider).valueOrNull == 'landlord';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Text(isLandlord ? 'Money' : 'Pay',
            style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
        actions: [
          if (isLandlord)
            IconButton(
              tooltip: 'New bill',
              icon: const Icon(Icons.add_rounded),
              onPressed: _newBill,
            ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: isLandlord
          ? KasaActionBar(children: [
              KasaButton(
                label: 'Record payment',
                variant: KasaButtonVariant.primary,
                onTap: _recordPayment,
              ),
            ])
          : null,
      body: KasaContentSwitcher(
        child: invoices.when(
          loading: () => const SkeletonList(),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined, size: 48, color: cs.kasaTextSub),
                const SizedBox(height: 12),
                Text(apiError(e), style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
                const SizedBox(height: 16),
                KasaButton(
                  label: 'Retry',
                  variant: KasaButtonVariant.secondary,
                  fullWidth: false,
                  onTap: () => ref.invalidate(invoicesProvider),
                ),
              ],
            ),
          ),
          data: (raw) {
            final all = raw.cast<Map<String, dynamic>>();
            // What needs chasing first: overdue, then due, then settled;
            // oldest first within each.
            int rank(Map<String, dynamic> b) => switch (b['status']) {
                  'overdue' => 0,
                  'partially_paid' || 'pending' => 1,
                  'paid' => 2,
                  _ => 3,
                };
            final shown = all.where(_matches).toList()
              ..sort((a, b) {
                final byRank = rank(a).compareTo(rank(b));
                return byRank != 0 ? byRank : '${a['due_date']}'.compareTo('${b['due_date']}');
              });
            final outstanding = all
                .where((b) => b['status'] != 'paid' && b['status'] != 'cancelled')
                .fold<double>(0, (sum, b) => sum + toDouble(b['balance']));
            int count(String f) => f == 'all'
                ? all.length
                : all.where((b) => switch (f) {
                      'overdue' => b['status'] == 'overdue',
                      'due' => _due.contains(b['status']),
                      _ => b['status'] == 'paid',
                    }).length;

            // WHY the empty state is refreshable too: a landlord who opened
            // this before the month's bills were raised was otherwise stuck
            // on "No bills" until the app restarted.
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (isLandlord) ...[
                    const _MoneyShortcuts(),
                    const SizedBox(height: 16),
                    const _PaymentsToAssign(),
                  ],
                  _ViewSwitch(
                    showPayments: _showPayments,
                    onChanged: (v) => setState(() => _showPayments = v),
                  ),
                  const SizedBox(height: 16),
                  if (_showPayments) const _PaymentsReceived() else ...[
                  KasaSectionHeader(
                    'Bills',
                    trailing: Text('${formatCurrency(outstanding)} outstanding',
                        style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)
                            .copyWith(fontFeatures: KasaType.tabular)),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (value, label) in const [
                        ('all', 'All'),
                        ('overdue', 'Overdue'),
                        ('due', 'Due'),
                        ('paid', 'Paid'),
                      ]) ...[
                        _FilterPill(
                          label: label,
                          count: count(value),
                          selected: _filter == value,
                          onTap: () => setState(() => _filter = value),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        _filter == 'all'
                            ? 'No bills yet. They are raised automatically on the 1st of each month.'
                            : 'Nothing here.',
                        textAlign: TextAlign.center,
                        style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
                      ),
                    )
                  else
                    KasaListGroup(children: [
                      for (final bill in shown)
                        _BillRow(invoice: bill, onChanged: () => ref.invalidate(invoicesProvider)),
                    ]),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// Money: shortcuts, payments to assign, filter pill

/// Reports and the tax statement, which live with the money they describe.
class _MoneyShortcuts extends StatelessWidget {
  const _MoneyShortcuts();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tile(IconData icon, String label, String route) => Expanded(
          child: KasaCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            onTap: () => context.push(route),
            child: Row(children: [
              Icon(icon, size: 20, color: cs.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.kasaTextSub),
            ]),
          ),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tile(Icons.description_outlined, 'Reports', '/reports'),
        const SizedBox(width: 8),
        tile(Icons.receipt_outlined, 'Tax statement', '/tax'),
      ]),
    );
  }
}

/// Money that arrived but could not be placed, each with an Assign button.
/// Shown only while something is waiting.
class _PaymentsToAssign extends ConsumerWidget {
  const _PaymentsToAssign();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(unplacedPaymentsProvider).valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    String detail(Map<String, dynamic> r) {
      final when = DateTime.tryParse('${r['credited_at']}');
      final ref0 = '${r['payment_ref'] ?? ''}'.trim();
      return [
        '${r['bank_display'] ?? ''}',
        if ('${r['payer_account'] ?? ''}'.isNotEmpty) '${r['payer_account']}',
        if (when != null) _displayDate.format(when.toLocal()),
        if (ref0.isNotEmpty) 'acct \u201c$ref0\u201d',
      ].join(' \u00b7 ');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KasaSectionHeader('Payments to assign',
              trailing: Text('${rows.length}',
                  style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub))),
          const SizedBox(height: 8),
          KasaListGroup(children: [
            for (final r in rows)
              KasaListRow(
                leading: const KasaLeadIcon(Icons.account_balance_wallet_outlined,
                    tone: KasaStatusKind.due),
                title: formatCurrency(toDouble(r['amount'])),
                subtitle: detail(r),
                trailing: KasaButton(
                  label: 'Assign',
                  variant: KasaButtonVariant.secondary,
                  fullWidth: false,
                  compact: true,
                  onTap: () => assignUnplacedPayment(context, ref, r),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.kasaBg : cs.onSurface;
    return Material(
      color: selected ? cs.onSurface : cs.kasaCard,
      shape: StadiumBorder(side: BorderSide(color: selected ? cs.onSurface : cs.kasaStrokeStrong)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label ', style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w500, color: fg)),
              TextSpan(
                text: '$count',
                style: KasaFont.sans(
                  fontSize: 14,
                  color: selected ? fg.withValues(alpha: 0.7) : cs.kasaTextSub,
                ).copyWith(fontFeatures: KasaType.tabular),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// Bills | Payments

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.showPayments, required this.onChanged});
  final bool showPayments;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget half(String label, bool on, bool value) => Expanded(
          child: Semantics(
            selected: on,
            button: true,
            child: Material(
              color: on ? cs.kasaCard : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(value),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  child: Text(label,
                      style: KasaFont.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: on ? cs.onSurface : cs.kasaTextSub,
                      )),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.kasaElev, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        half('Bills', !showPayments, false),
        const SizedBox(width: 4),
        half('Payments', showPayments, true),
      ]),
    );
  }
}

/// Money that came in: who paid, for which unit, how, and the receipt.
/// Searchable, because the question is usually about one person.
class _PaymentsReceived extends ConsumerStatefulWidget {
  const _PaymentsReceived();

  @override
  ConsumerState<_PaymentsReceived> createState() => _PaymentsReceivedState();
}

class _PaymentsReceivedState extends ConsumerState<_PaymentsReceived> {
  String _query = '';

  bool _matches(Map<String, dynamic> p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      p['tenant_name'], p['unit_number'], p['property_name'],
      p['mpesa_receipt_number'], p['mpesa_phone'], p['bank_reference'],
    ].any((v) => '${v ?? ''}'.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final payments = ref.watch(paymentsReceivedProvider);
    return payments.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(apiError(e), textAlign: TextAlign.center),
      ),
      data: (all) {
        final now = DateTime.now();
        // What arrived this month, not the deposit applied at a move-out,
        // which arrived at move-in and was counted then.
        final thisMonth = all
            .where((p) {
              final d = DateTime.tryParse('${p['paid_at']}')?.toLocal();
              return d != null && d.year == now.year && d.month == now.month && p['method'] != 'deposit';
            })
            .fold<double>(0, (sum, p) => sum + toDouble(p['amount']));
        final shown = all.where(_matches).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KasaSectionHeader(
              'Payments',
              trailing: Text('${formatCurrency(thisMonth)} in ${DateFormat('MMMM').format(now)}',
                  style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)
                      .copyWith(fontFeatures: KasaType.tabular)),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Name, unit, phone or receipt',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  all.isEmpty ? 'No payments yet.' : 'No payment matches \u201c$_query\u201d.',
                  textAlign: TextAlign.center,
                  style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
                ),
              )
            else
              KasaListGroup(children: [for (final p in shown) _PaymentRow(payment: p)]),
          ],
        );
      },
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});
  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final when = DateTime.tryParse('${payment['paid_at']}')?.toLocal();
    final receipt = '${payment['mpesa_receipt_number'] ?? payment['bank_reference'] ?? ''}'.trim();
    final detail = [
      '${payment['method_display'] ?? ''}',
      if (when != null) DateFormat('d MMM, HH:mm').format(when),
    ].join(' \u00b7 ');

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.kasaElev, borderRadius: BorderRadius.circular(10)),
            child: Text('${payment['unit_number'] ?? ''}',
                maxLines: 1,
                style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${payment['tenant_name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KasaFont.sans(fontSize: 15, fontWeight: FontWeight.w500, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(detail, style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
                if (receipt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(receipt, style: KasaFont.mono(fontSize: 12, color: cs.kasaTextSub)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatCurrency(toDouble(payment['amount'])),
              style: KasaFont.sans(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)
                  .copyWith(fontFeatures: KasaType.tabular)),
        ]),
      ),
    );
  }
}

// Bill row

/// One bill: unit, tenant, when it was due, what is left, and its status.
class _BillRow extends ConsumerWidget {
  const _BillRow({required this.invoice, required this.onChanged});
  final Map<String, dynamic> invoice;
  final VoidCallback onChanged;

  static (KasaStatusKind, String) statusOf(String? status) => switch (status) {
        'paid' => (KasaStatusKind.paid, 'Paid'),
        'overdue' => (KasaStatusKind.overdue, 'Overdue'),
        'partially_paid' => (KasaStatusKind.due, 'Part paid'),
        'cancelled' => (KasaStatusKind.vacant, 'Void'),
        _ => (KasaStatusKind.due, 'Due'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final status = statusOf(invoice['status'] as String?);
    final due = DateTime.tryParse('${invoice['due_date']}');
    final isPaid = invoice['status'] == 'paid';
    return InkWell(
      onTap: () => _showDetail(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.kasaElev,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${invoice['unit_number'] ?? ''}',
                  maxLines: 1,
                  style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${invoice['tenant_name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KasaFont.sans(fontSize: 15, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    due == null ? '' : '${isPaid ? 'Was due' : 'Due'} ${_displayDate.format(due)}',
                    style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(toDouble(invoice['balance'])),
                    style: KasaFont.sans(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)
                        .copyWith(fontFeatures: KasaType.tabular)),
                const SizedBox(height: 4),
                KasaStatusChip(kind: status.$1, label: status.$2),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  // WHY a route on the tab's own navigator and not a sheet: the bill has its
  // own back button and actions, and the tab bar stays where it was.
  void _showDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _InvoiceDetailScreen(invoice: invoice, onChanged: onChanged),
      ),
    );
  }
}

// Bill detail

class _InvoiceDetailScreen extends ConsumerStatefulWidget {
  const _InvoiceDetailScreen({required this.invoice, required this.onChanged});
  final Map<String, dynamic> invoice;
  final VoidCallback onChanged;

  @override
  ConsumerState<_InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<_InvoiceDetailScreen> {
  bool _stkLoading = false;

  /// The bill as the list now holds it, so recording a payment or adding an
  /// eTIMS receipt shows here without leaving the screen. Falls back to the
  /// copy this screen was opened with.
  Map<String, dynamic> get invoice {
    for (final row in ref.read(invoicesProvider).valueOrNull ?? const []) {
      if (row is Map && row['id'] == widget.invoice['id']) {
        return Map<String, dynamic>.from(row);
      }
    }
    return widget.invoice;
  }

  VoidCallback get onChanged => widget.onChanged;

  Future<void> _stkPush(BuildContext context, WidgetRef ref) async {
    setState(() => _stkLoading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/api/v1/payments/stk/push/', data: {
        'invoice_id': invoice['id'],
      });
      final checkoutId = resp.data['checkout_request_id'] as String?;
      setState(() {
        _stkLoading = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('M-Pesa prompt sent! Check your phone.'),
          backgroundColor: KasaChannel.mpesa,
          duration: Duration(seconds: 5),
        ));
        // Poll for completion every 3 seconds, up to 60 seconds
        _pollStkStatus(checkoutId!);
      }
    } catch (e) {
      setState(() => _stkLoading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<void> _pollStkStatus(String checkoutId) async {
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final dio = ref.read(dioProvider);
        final resp = await dio.get(
          '/api/v1/payments/stk/status/',
          queryParameters: {'checkout_request_id': checkoutId},
        );
        final stkStatus = resp.data['status'] as String?;
        if (stkStatus == 'success') {
          onChanged(); // refresh invoice list
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Payment confirmed! Invoice updated.'),
              backgroundColor: KasaChannel.mpesa,
            ));
            Navigator.of(context).pop();
          }
          return;
        } else if (stkStatus == 'failed' || stkStatus == 'cancelled') {
          final desc = resp.data['result_desc'] ?? 'Payment was not completed.';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(desc.toString()),
              backgroundColor: Theme.of(context).colorScheme.error,
            ));
          }
          return;
        } else if (stkStatus == 'requires_review') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text(
                'M-Pesa reported success, but the receipt still needs verification. '
                'Do not pay again; contact your landlord if it remains pending.',
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiary,
            ));
          }
          return;
        }
      } catch (_) {
        // ignore poll errors silently
      }
    }
    // Timed out polling — tell user to check manually
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Payment status unknown. Refresh invoices to check.'),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
      ));
    }
  }

  void _showPaymentMethodSheet(BuildContext context, WidgetRef ref) {
    final balance = double.tryParse((invoice['balance'] ?? '0').toString()) ?? 0;
    final role = ref.read(userRoleProvider).valueOrNull;
    final isTenant = role == 'tenant';

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _PaymentMethodSheet(
        invoice: invoice,
        balance: balance,
        isTenant: isTenant,
        onStkPush: () {
          Navigator.pop(ctx);
          _stkPush(context, ref);
        },
        onManualPayment: isTenant
            ? null
            : () {
                Navigator.pop(ctx);
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    useRootNavigator: true,
                    barrierDismissible: false,
                    builder: (_) => _RecordPaymentDialog(
                      invoiceId: invoice['id'] as int,
                      balance: balance,
                      onDone: onChanged,
                    ),
                  );
                });
              },
      ),
    );
  }

  Future<void> _sendReminder() async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(dioProvider)
          .post('/api/v1/payments/invoices/${invoice['id']}/remind/');
      messenger.showSnackBar(SnackBar(
        content: Text('Reminder sent to ${invoice['tenant_name'] ?? 'the tenant'}.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiError(e)), backgroundColor: errorColor));
    }
  }

  Future<void> _voidBill() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Void this bill?'),
        content: Text('Mark ${invoice['invoice_number']} as cancelled? '
            'No payments or ledger entries will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Void')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(dioProvider).post('/api/v1/payments/invoices/${invoice['id']}/cancel/');
      onChanged();
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Bill voided.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiError(e)), backgroundColor: errorColor));
    }
  }

  String _plain(num n) => NumberFormat('#,##0').format(n);

  /// "was due 5 Sep, 23 days ago" / "due 5 Oct, in 12 days" / "due today".
  String _dueLine(String status, DateTime? due) {
    if (status == 'paid') return 'Settled';
    if (status == 'cancelled') return 'Voided';
    if (due == null) return '';
    final today = DateTime.now();
    final days = DateTime(due.year, due.month, due.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    final on = DateFormat('d MMM').format(due);
    if (days == 0) return 'Due today';
    if (days > 0) return 'Due $on, in $days ${days == 1 ? 'day' : 'days'}';
    return 'Was due $on, ${-days} ${days == -1 ? 'day' : 'days'} ago';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(invoicesProvider); // rebuild when the list changes
    final cs = Theme.of(context).colorScheme;
    final bill = invoice;
    final status = bill['status'] as String? ?? '';
    final isLandlord = ref.watch(userRoleProvider).valueOrNull == 'landlord';
    final isOpen = status != 'paid' && status != 'cancelled';
    final canEdit = isLandlord && (status == 'pending' || status == 'overdue');
    final canVoid = canEdit;
    final lines = (bill['line_items'] as List? ?? const []).cast<Map<String, dynamic>>();
    final payments = (bill['payments'] as List? ?? const []).cast<Map<String, dynamic>>();
    final period = DateTime.tryParse('${bill['period_start']}');
    final due = DateTime.tryParse('${bill['due_date']}');
    final balance = toDouble(bill['balance']);
    final chip = _BillRow.statusOf(status);
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);
    final amount = KasaFont.sans(fontSize: 14, color: cs.onSurface)
        .copyWith(fontFeatures: KasaType.tabular);

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Text(period == null ? 'Bill' : '${DateFormat('MMMM').format(period)} bill',
            style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
        actions: [
          if (canEdit || canVoid)
            PopupMenuButton<String>(
              tooltip: 'Bill options',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) {
                if (v == 'edit') {
                  showDialog(
                    context: context,
                    useRootNavigator: true,
                    barrierDismissible: false,
                    builder: (_) => _EditInvoiceDialog(invoice: bill, onDone: onChanged),
                  );
                } else if (v == 'void') {
                  _voidBill();
                }
              },
              itemBuilder: (_) => [
                if (canEdit)
                  const PopupMenuItem(value: 'edit', child: Text('Edit bill')),
                if (canVoid)
                  const PopupMenuItem(value: 'void', child: Text('Void bill')),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: !isOpen
          ? null
          : KasaActionBar(children: [
              if (isLandlord)
                _SquareIconButton(
                  icon: Icons.sms_outlined,
                  tooltip: 'Send reminder SMS',
                  onTap: _sendReminder,
                ),
              KasaButton(
                label: isLandlord ? 'Record payment' : 'Pay ${formatCurrency(balance)} with M-Pesa',
                variant: KasaButtonVariant.primary,
                isLoading: _stkLoading,
                onTap: _stkLoading ? null : () => _showPaymentMethodSheet(context, ref),
              ),
            ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('${bill['tenant_name'] ?? ''} \u00b7 Unit ${bill['unit_number'] ?? ''}', style: muted),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(formatCurrency(balance),
                  style: KasaType.moneyXl.copyWith(color: cs.onSurface)),
            ),
            KasaStatusChip(kind: chip.$1, label: chip.$2),
          ]),
          const SizedBox(height: 8),
          Text('Balance \u00b7 ${_dueLine(status, due)}', style: muted),
          const SizedBox(height: 4),
          Text('${bill['invoice_number'] ?? ''}',
              style: KasaFont.mono(fontSize: 12, color: cs.kasaTextSub)),
          const SizedBox(height: 16),

          KasaCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(children: [
                  if (lines.isEmpty)
                    KasaKeyValue('Amount due', Text(_plain(toDouble(bill['amount_due'])), style: amount))
                  else
                    for (final li in lines) _LineItemRow(item: li, amount: amount),
                ]),
              ),
              Divider(height: 1, color: cs.kasaStroke),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(children: [
                  KasaKeyValue('Total',
                      Text(formatCurrency(toDouble(bill['amount_due'])),
                          style: amount.copyWith(fontWeight: FontWeight.w600)),
                      strong: true),
                  if (toDouble(bill['amount_paid']) > 0)
                    KasaKeyValue('Paid',
                        Text('\u2212 ${_plain(toDouble(bill['amount_paid']))}', style: amount)),
                  KasaKeyValue('Balance',
                      Text(formatCurrency(balance),
                          style: amount.copyWith(fontWeight: FontWeight.w600)),
                      strong: true),
                ]),
              ),
            ]),
          ),
          if ('${bill['notes'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Notes: ${bill['notes']}', style: muted),
          ],
          const SizedBox(height: 20),

          const KasaSectionHeader('Payments'),
          const SizedBox(height: 8),
          if (payments.isEmpty)
            KasaCard(
              padding: const EdgeInsets.all(16),
              child: Text('No payments recorded yet.', style: muted),
            )
          else
            KasaListGroup(children: [
              for (final pm in payments)
                _BillPaymentRow(
                  payment: pm,
                  canAddReceipt: isLandlord,
                  onAddReceipt: () => _captureEtimsReceipt(context, ref, pm['id'] as int),
                ),
            ]),
        ],
      ),
    );
  }
}

/// One line of the bill. A metered charge also shows the readings it came from,
/// which is what settles a dispute about the water.
class _LineItemRow extends StatelessWidget {
  const _LineItemRow({required this.item, required this.amount});
  final Map<String, dynamic> item;
  final TextStyle amount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metered = item['previous_reading'] != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['description'] ?? ''}',
                    style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
                if (metered)
                  Text(
                    '${toDouble(item['current_reading']).toStringAsFixed(0)} \u2212 '
                    '${toDouble(item['previous_reading']).toStringAsFixed(0)} = '
                    '${toDouble(item['units_consumed']).toStringAsFixed(0)} units '
                    '\u00d7 ${AppConstants.currency} ${toDouble(item['unit_price']).toStringAsFixed(2)}',
                    style: KasaFont.mono(fontSize: 11, color: cs.kasaTextSub),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(NumberFormat('#,##0').format(toDouble(item['amount'])), style: amount),
        ],
      ),
    );
  }
}

/// A payment against this bill: how, when, the receipt, and (for the
/// landlord) the eTIMS receipt KRA will check the rent against.
class _BillPaymentRow extends StatelessWidget {
  const _BillPaymentRow({
    required this.payment,
    required this.canAddReceipt,
    required this.onAddReceipt,
  });

  final Map<String, dynamic> payment;
  final bool canAddReceipt;
  final VoidCallback onAddReceipt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final when = DateTime.tryParse('${payment['paid_at']}')?.toLocal();
    final receipt = '${payment['mpesa_receipt_number'] ?? payment['bank_reference'] ?? ''}'.trim();
    final bank = [
      if ('${payment['bank_name'] ?? ''}'.isNotEmpty) '${payment['bank_name']}',
      if ('${payment['bank_account'] ?? ''}'.isNotEmpty) 'from ${payment['bank_account']}',
      if ('${payment['bank_branch'] ?? ''}'.isNotEmpty) '${payment['bank_branch']} branch',
    ].join(' \u00b7 ');
    final etims = '${payment['etims_receipt_number'] ?? ''}'.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KasaLeadIcon(Icons.phone_iphone_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    '${payment['method_display'] ?? ''}',
                    if (when != null) DateFormat('d MMM').format(when),
                  ].join(' \u00b7 '),
                  style: KasaFont.sans(fontSize: 15, fontWeight: FontWeight.w500, color: cs.onSurface),
                ),
                if (receipt.isNotEmpty)
                  Text(receipt, style: KasaFont.mono(fontSize: 12, color: cs.kasaTextSub)),
                if (bank.isNotEmpty)
                  Text(bank, style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
                // KRA checks declared rent against eTIMS records, so the
                // receipt sits on the payment it belongs to.
                if (canAddReceipt) ...[
                  const SizedBox(height: 4),
                  if (etims.isNotEmpty)
                    Text('eTIMS $etims', style: KasaFont.mono(fontSize: 12, color: cs.kasaTextSub))
                  else
                    InkWell(
                      onTap: onAddReceipt,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('+ Add eTIMS receipt',
                            style: KasaFont.sans(
                                fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(NumberFormat('#,##0').format(toDouble(payment['amount'])),
              style: KasaFont.sans(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)
                  .copyWith(fontFeatures: KasaType.tabular)),
        ],
      ),
    );
  }
}

/// The small outlined square beside the primary action.
class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.kasaCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.kasaStrokeStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 52, height: 52, child: Icon(icon, color: cs.onSurface)),
        ),
      ),
    );
  }
}

// ─── Edit Invoice Dialog ──────────────────────────────────────────────────────

class _EditInvoiceDialog extends ConsumerStatefulWidget {
  const _EditInvoiceDialog({required this.invoice, required this.onDone});
  final Map<String, dynamic> invoice;
  final VoidCallback onDone;

  @override
  ConsumerState<_EditInvoiceDialog> createState() => _EditInvoiceDialogState();
}

class _EditInvoiceDialogState extends ConsumerState<_EditInvoiceDialog> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _dueDate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: (widget.invoice['amount_due'] ?? '').toString());
    _notesCtrl = TextEditingController(
        text: (widget.invoice['notes'] ?? '').toString());
    _dueDate = widget.invoice['due_date'] != null
        ? DateTime.tryParse(widget.invoice['due_date']) ?? DateTime.now()
        : DateTime.now();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/api/v1/payments/invoices/${widget.invoice['id']}/', data: {
        'amount_due': amount,
        'due_date': _apiDate.format(_dueDate),
        'notes': _notesCtrl.text.trim(),
      });
      widget.onDone();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invoice updated.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Invoice'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Amount Due (${AppConstants.currency}) *',
                  prefixText: '${AppConstants.currency} ',
                  isDense: true),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null && mounted) {
                  setState(() => _dueDate = picked);
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Due Date',
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today, size: 16),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Text(_displayDate.format(_dueDate),
                    style: const TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)', isDense: true),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
// ─── Payment Method Sheet ─────────────────────────────────────────────────────

class _PaymentMethodSheet extends StatelessWidget {
  const _PaymentMethodSheet({
    required this.invoice,
    required this.balance,
    required this.isTenant,
    required this.onStkPush,
    required this.onManualPayment,
  });

  final Map<String, dynamic> invoice;
  final double balance;
  final bool isTenant;
  final VoidCallback onStkPush;
  final VoidCallback? onManualPayment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final invoiceNo = invoice['invoice_number'] as String? ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(
            'Pay invoice',
            style: KasaFont.sans(
              fontSize: 22, fontWeight: FontWeight.w600,
              letterSpacing: -0.44, color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Invoice $invoiceNo · Balance ${formatCurrency(balance)}',
            style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub),
          ),
          const SizedBox(height: 20),

          // ── M-Pesa STK Push ───────────────────────────────────────────
          _MethodTile(
            icon: Icons.phone_android_outlined,
            color: KasaChannel.mpesa,
            title: 'M-Pesa (STK Push)',
            subtitle: 'We\'ll send a payment prompt directly to your phone.',
            onTap: onStkPush,
          ),

          const SizedBox(height: 10),

          // ── M-Pesa Paybill (manual) ───────────────────────────────────
          _MethodTile(
            icon: Icons.dialpad_outlined,
            color: KasaChannel.paybill,
            title: 'M-Pesa Paybill',
            subtitle: 'Pay manually via Lipa na M-Pesa then wait for confirmation.',
            onTap: () {
              Navigator.pop(context);
              _showPaybillInstructions(context, invoice);
            },
          ),

          // ── Bank Transfer (landlord only) ─────────────────────────────
          if (!isTenant) ...[
            const SizedBox(height: 10),
            _MethodTile(
              icon: Icons.account_balance_outlined,
              color: KasaChannel.bank,
              title: 'Bank Transfer',
              subtitle: 'Record a payment received via bank transfer.',
              onTap: onManualPayment ?? () {},
            ),
          ],

          // ── Cash ──────────────────────────────────────────────────────
          if (!isTenant) ...[
            const SizedBox(height: 10),
            _MethodTile(
              icon: Icons.payments_outlined,
              color: KasaChannel.cash,
              title: 'Cash',
              subtitle: 'Tenant pays in cash. Record when received.',
              onTap: onManualPayment ?? () {},
            ),
          ] else ...[
            const SizedBox(height: 10),
            _MethodTile(
              icon: Icons.payments_outlined,
              color: KasaChannel.cash,
              title: 'Cash',
              subtitle: 'Pay your landlord in cash and wait for them to confirm.',
              onTap: () {
                Navigator.pop(context);
                _showCashInstructions(context);
              },
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showPaybillInstructions(
      BuildContext context, Map<String, dynamic> invoice) {
    final unitNo = invoice['unit_number']?.toString() ?? '—';
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Icon(Icons.dialpad_outlined,
                  color: Theme.of(ctx).colorScheme.secondary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Lipa na M-Pesa',
                style: KasaFont.sans(
                  fontSize: 18, fontWeight: FontWeight.w600,
                  letterSpacing: -0.36,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
            ]),
            const SizedBox(height: 20),
            const _InstructionStep(
                n: 1, text: 'Open M-Pesa on your phone'),
            const _InstructionStep(
                n: 2, text: 'Select  Lipa na M-Pesa  →  Pay Bill'),
            _InstructionStep(
                n: 3,
                label: 'Business No.',
                value: invoice['mpesa_paybill']?.toString() ?? 'Ask your landlord'),
            _InstructionStep(
                n: 4,
                label: 'Account No.',
                value: invoice['pay_account']?.toString() ?? unitNo),
            _InstructionStep(
                n: 5,
                label: 'Amount',
                value: formatCurrency(
                    double.tryParse((invoice['balance'] ?? '0').toString()) ??
                        0)),
            const _InstructionStep(
                n: 6, text: 'Enter your M-Pesa PIN and confirm'),
            const SizedBox(height: 16),
            KasaCard(
              accent: KasaCardAccent.secondary,
              padding: const EdgeInsets.all(12),
              showShadow: false,
              child: Row(children: [
                Icon(Icons.info_outline,
                    color: Theme.of(ctx).colorScheme.onSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your invoice will update automatically once payment is confirmed.',
                    style: KasaFont.sans(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSecondary,
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _showCashInstructions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(children: [
                Icon(Icons.payments_outlined, color: cs.tertiary, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Cash payment',
                  style: KasaFont.sans(
                    fontSize: 18, fontWeight: FontWeight.w600,
                    letterSpacing: -0.36, color: cs.onSurface,
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              _InstructionStep(
                  n: 1,
                  text: 'Hand the cash payment of ${formatCurrency(balance)} to your landlord or caretaker.'),
              const _InstructionStep(
                  n: 2, text: 'Ask for a signed receipt.'),
              const _InstructionStep(
                  n: 3,
                  text: 'Wait for your landlord to record the payment — your invoice will update once confirmed.'),
              const SizedBox(height: 16),
              KasaCard(
                accent: KasaCardAccent.tertiary,
                padding: const EdgeInsets.all(12),
                showShadow: false,
                child: Row(children: [
                  Icon(Icons.warning_amber_outlined,
                      color: cs.tertiaryInk, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cash payments must be confirmed by your landlord. If your invoice is not updated within 24 hours, contact them directly.',
                      style: KasaFont.sans(fontSize: 12, color: cs.tertiaryInk),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return KasaCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KasaFont.sans(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    letterSpacing: -0.14, color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: KasaFont.sans(fontSize: 12, color: cs.kasaTextSub),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.kasaTextSub, size: 18),
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.n, this.text, this.label, this.value});
  final int n;
  final String? text;
  final String? label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
            ),
            alignment: Alignment.center,
            child: Text(
              '$n',
              style: KasaFont.sans(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: cs.onSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: text != null
                ? Text(
                    text!,
                    style: KasaFont.sans(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$label  ',
                        style: KasaFont.sans(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          letterSpacing: 0.04, color: cs.kasaTextSub,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          value ?? '—',
                          style: KasaFont.mono(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Record Payment Dialog ────────────────────────────────────────────────────

class _RecordPaymentDialog extends ConsumerStatefulWidget {
  const _RecordPaymentDialog({
    required this.invoiceId,
    required this.balance,
    required this.onDone,
  });
  final int invoiceId;
  final double balance;
  final VoidCallback onDone;

  @override
  ConsumerState<_RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
  String _method = 'cash';
  late final TextEditingController _amountCtrl;
  // Bank-specific controllers
  String? _bankName;
  final _bankAccountCtrl = TextEditingController();
  final _bankReferenceCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  bool _loading = false;

  static const _methods = [
    ('cash', 'Cash'),
    ('bank', 'Bank Transfer'),
  ];

  static const _kenyanBanks = [
    'KCB', 'Equity Bank', 'Co-operative Bank', 'NCBA', 'Absa Kenya',
    'Standard Chartered', 'DTB', 'I&M Bank', 'Family Bank', 'Stanbic',
    'Prime Bank', 'HF Group', 'GT Bank', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.balance.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankReferenceCtrl.dispose();
    _bankBranchCtrl.dispose();
    super.dispose();
  }

  bool get _isBank => _method == 'bank';

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount.')),
      );
      return;
    }
    if (_isBank && _bankReferenceCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bank reference / transaction ID is required.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/api/v1/payments/record/', data: {
        'invoice': widget.invoiceId,
        'method': _method,
        'amount': amount,
        if (_isBank) ...{
          if (_bankName != null) 'bank_name': _bankName,
          if (_bankAccountCtrl.text.trim().isNotEmpty)
            'bank_account': _bankAccountCtrl.text.trim(),
          'bank_reference': _bankReferenceCtrl.text.trim(),
          if (_bankBranchCtrl.text.trim().isNotEmpty)
            'bank_branch': _bankBranchCtrl.text.trim(),
        },
      });
      widget.onDone();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment recorded successfully.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        _isBank ? 'Record Bank Transfer' : 'Record Cash Payment',
        style: KasaFont.sans(fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Method ──────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Payment Method'),
              items: _methods
                  .map((m) => DropdownMenuItem(value: m.$1, child: Text(m.$2)))
                  .toList(),
              onChanged: (v) => setState(() => _method = v!),
            ),
            const SizedBox(height: 12),

            // ── Amount ──────────────────────────────────────────────────
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Amount (${AppConstants.currency})',
                prefixText: '${AppConstants.currency} ',
              ),
              keyboardType: TextInputType.number,
            ),

            // ── Bank-specific fields ────────────────────────────────────
            if (_isBank) ...[
              const SizedBox(height: 16),
              Divider(color: cs.outlineVariant, thickness: 1),
              const SizedBox(height: 8),
              Text(
                'Bank details',
                style: KasaFont.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.04,
                  color: cs.kasaTextSub,
                ),
              ),
              const SizedBox(height: 10),

              // Bank name
              DropdownButtonFormField<String>(
                initialValue: _bankName,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bank Name'),
                hint: const Text('Select bank…'),
                items: _kenyanBanks
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setState(() => _bankName = v),
              ),
              const SizedBox(height: 10),

              // Sender account / phone
              TextFormField(
                controller: _bankAccountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sender Account / Phone',
                  hintText: 'e.g. 1234567890 or 0712 345 678',
                  prefixIcon: Icon(Icons.account_box_outlined),
                ),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 10),

              // Transaction reference — required
              TextFormField(
                controller: _bankReferenceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Transaction Ref / Slip No. *',
                  hintText: 'e.g. FT25001234567',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 10),

              // Branch — optional
              TextFormField(
                controller: _bankBranchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Branch (optional)',
                  hintText: 'e.g. Westlands',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Record'),
        ),
      ],
    );
  }
}

// ─── Create Invoice Dialog ────────────────────────────────────────────────────

class _CreateInvoiceDialog extends ConsumerStatefulWidget {
  const _CreateInvoiceDialog({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_CreateInvoiceDialog> createState() =>
      _CreateInvoiceDialogState();
}

class _CreateInvoiceDialogState extends ConsumerState<_CreateInvoiceDialog> {
  List<Map<String, dynamic>> _tenancies = [];
  bool _initialLoading = true;
  String? _loadError;

  int? _selectedTenancyId;
  final _notesCtrl = TextEditingController();
  DateTime _periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  // Day 0 of next month = last day of current month (Dart overflow handling).
  // Explicitly guard December (month 12) by using year+1, month 1, day 0.
  static DateTime _lastDayOfMonth(int year, int month) {
    if (month == 12) return DateTime(year + 1, 1, 0);
    return DateTime(year, month + 1, 0);
  }
  late DateTime _periodEnd = _lastDayOfMonth(DateTime.now().year, DateTime.now().month);
  DateTime _dueDate = DateTime(DateTime.now().year, DateTime.now().month, 5);
  bool _submitting = false;

  List<_LineItemEntry> _lineItems = [];
  bool _loadingCharges = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadTenancies);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final item in _lineItems) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTenancies() async {
    try {
      final dio = ref.read(dioProvider);
      final raw = await fetchAllPages(
        dio,
        '/api/v1/tenants/tenancies/',
        queryParameters: {'status': 'active'},
      );
      if (!mounted) return;
      setState(() {
        _tenancies = raw.cast<Map<String, dynamic>>();
        _initialLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _loadError = apiError(e);
        });
      }
    }
  }

  Future<void> _loadPropertyCharges(double rentAmount, int? propertyId) async {
    setState(() => _loadingCharges = true);
    List<Map<String, dynamic>> charges = [];
    try {
      if (propertyId != null) {
        final dio = ref.read(dioProvider);
        final data = await fetchAllPages(
          dio,
          '/api/v1/properties/charges/',
          queryParameters: {'property': propertyId, 'is_active': 'true'},
        );
        charges = data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not load charges: ${apiError(e)}'),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
        ));
      }
    }
    if (!mounted) return;
    for (final item in _lineItems) {
      item.dispose();
    }
    final newItems = [
      _LineItemEntry(
        chargeType: 'rent',
        description: 'Monthly Rent',
        isMetered: false,
        initialAmount: rentAmount,
      ),
      ...charges.map((c) => _LineItemEntry(
            chargeType: c['charge_type'] as String,
            description: c['name'] as String,
            isMetered: c['billing_method'] == 'metered',
            unitPrice: double.tryParse((c['unit_price'] ?? '0').toString()),
            initialAmount: c['billing_method'] == 'flat'
                ? double.tryParse((c['unit_price'] ?? '0').toString()) ?? 0
                : 0,
          )),
    ];
    for (final item in newItems) {
      item.amountCtrl.addListener(_refreshTotal);
      item.prevCtrl.addListener(_refreshTotal);
      item.currCtrl.addListener(_refreshTotal);
    }
    setState(() {
      _loadingCharges = false;
      _lineItems = newItems;
    });
  }

  void _refreshTotal() {
    if (mounted) setState(() {});
  }

  Future<void> _pickDate(String field) async {
    final initial = field == 'start'
        ? _periodStart
        : field == 'end'
            ? _periodEnd
            : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (field == 'start') _periodStart = picked;
        if (field == 'end') _periodEnd = picked;
        if (field == 'due') _dueDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedTenancyId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a tenancy.')));
      return;
    }

    final active = _lineItems.where((i) => i.enabled).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least one line item is required.')));
      return;
    }

    for (final item in active) {
      if (item.isMetered) {
        final prev = double.tryParse(item.prevCtrl.text);
        final curr = double.tryParse(item.currCtrl.text);
        if (prev == null || curr == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Enter meter readings for ${item.description}.')),
          );
          return;
        }
        if (curr < prev) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${item.description}: current reading must be ≥ previous.')),
          );
          return;
        }
      }
    }

    final total = active.fold(0.0, (sum, i) => sum + i.computedAmount);
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Total must be greater than zero.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/api/v1/payments/invoices/', data: {
        'tenancy': _selectedTenancyId,
        'amount_due': total,
        'period_start': _apiDate.format(_periodStart),
        'period_end': _apiDate.format(_periodEnd),
        'due_date': _apiDate.format(_dueDate),
        'notes': _notesCtrl.text.trim(),
        'line_items': active.map((i) => i.toMap()).toList(),
      });
      widget.onDone();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invoice created successfully.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildLineItemRow(_LineItemEntry item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Checkbox(
                value: item.enabled,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => item.enabled = v!),
              ),
              Expanded(
                child: Text(item.description,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Text(
                formatCurrency(item.enabled ? item.computedAmount : 0),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: item.enabled
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
              ),
            ],
          ),
          if (item.enabled) ...[
            if (item.isMetered) ...[
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: item.prevCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Prev reading', isDense: true),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    const SizedBox(
                      width: 32,
                      child: Center(
                        child: Text('→', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: item.currCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Curr reading', isDense: true),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                  ],
                ),
              ),
              if (item.prevCtrl.text.isNotEmpty &&
                  item.currCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 44, top: 4),
                  child: Builder(builder: (_) {
                    final prev = double.tryParse(item.prevCtrl.text) ?? 0;
                    final curr = double.tryParse(item.currCtrl.text) ?? 0;
                    final units = (curr - prev).clamp(0.0, double.infinity);
                    return Text(
                      '${units.toStringAsFixed(0)} units × '
                      '${AppConstants.currency} ${(item.unitPrice ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 11, color: theme.colorScheme.secondary),
                    );
                  }),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: TextFormField(
                  controller: item.amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '${AppConstants.currency} ',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _lineItems
        .where((i) => i.enabled)
        .fold(0.0, (s, i) => s + i.computedAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _initialLoading
              ? const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()))
              : _loadError != null
                  ? Center(child: Text(_loadError!, style: const TextStyle(color: Colors.red)))
                  : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tenancy picker
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                            labelText: 'Tenancy / Tenant *', isDense: true),
                        initialValue: _selectedTenancyId,
                        hint: _tenancies.isEmpty
                            ? const Text('No active tenancies')
                            : const Text('Select tenancy'),
                        isExpanded: true,
                        items: _tenancies
                            .map((l) => DropdownMenuItem<int>(
                                  value: l['id'] as int,
                                  child: Text(
                                    '${l['tenant_name']} – Unit ${l['unit_number']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedTenancyId = v;
                            for (final item in _lineItems) {
                              item.dispose();
                            }
                            _lineItems = [];
                          });
                          if (v != null) {
                            final tenancy = _tenancies.firstWhere(
                                (l) => l['id'] == v, orElse: () => {});
                            if (tenancy.isNotEmpty) {
                              final rentAmount = double.tryParse(
                                      (tenancy['rent_amount'] ?? '0')
                                          .toString()) ??
                                  0;
                              _loadPropertyCharges(
                                  rentAmount, tenancy['property_id'] as int?);
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      // Date row: Period start + end
                      Row(
                        children: [
                          Expanded(
                              child: _DateField(
                            label: 'Period Start',
                            value: _periodStart,
                            onTap: () => _pickDate('start'),
                          )),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _DateField(
                            label: 'Period End',
                            value: _periodEnd,
                            onTap: () => _pickDate('end'),
                          )),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Due date
                      _DateField(
                        label: 'Due Date',
                        value: _dueDate,
                        onTap: () => _pickDate('due'),
                      ),
                      const SizedBox(height: 14),

                      // Notes
                      TextFormField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            hintText: 'e.g. March 2026 rent',
                            isDense: true),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 20),

                      // ── Charges / Line Items ──────────────────────────────
                      if (_selectedTenancyId == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text('Select a tenancy to see charges.',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else if (_loadingCharges)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else ...[
                        Row(
                          children: [
                            Text('Charges',
                                style: theme.textTheme.titleSmall),
                            const Spacer(),
                            Text(
                              'Total: ${formatCurrency(total)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._lineItems.map(_buildLineItemRow),
                      ],
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
        ),

        // Action buttons
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(120, 48),
                ),
                onPressed:
                    (_submitting || _initialLoading || _loadingCharges)
                        ? null
                        : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Invoice'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Text(_displayDate.format(value),
            style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

/// Records the eTIMS receipt number KRA issued for a payment.
///
/// It cannot be captured when the money arrives — the landlord generates the
/// receipt on eTIMS afterwards — so it is added to the payment later, and it is
/// the only thing about a confirmed payment that may still be written.
Future<void> _captureEtimsReceipt(
  BuildContext context,
  WidgetRef ref,
  int paymentId,
) async {
  final controller = TextEditingController();
  final number = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: const Text('eTIMS receipt'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Receipt number',
              hintText: 'As issued on eTIMS',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          const SizedBox(height: 10),
          const Text(
            'KRA checks the rent you declare against their eTIMS records. '
            'Adding it here ties this payment to the receipt behind it.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (number == null || number.isEmpty || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    await ref.read(dioProvider).post(
      '/api/v1/payments/$paymentId/etims-receipt/',
      data: {'etims_receipt_number': number},
    );
    ref.invalidate(invoicesProvider);
    messenger.showSnackBar(const SnackBar(
      content: Text('eTIMS receipt recorded.'),
      backgroundColor: Colors.green,
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(apiError(e)),
      backgroundColor: errorColor,
    ));
  }
}
