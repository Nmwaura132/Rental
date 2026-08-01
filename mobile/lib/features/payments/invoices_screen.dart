import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/constants.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../shared/widgets/shimmer_loading.dart';

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

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoicesProvider);
    final role = ref.watch(userRoleProvider).valueOrNull;
    final isLandlord = role == 'landlord';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Sticky header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'INVOICES',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.96,
                      color: cs.onSurface,
                      height: 1,
                    ),
                  ),
                  const Spacer(),
                  if (isLandlord)
                    KasaButton(
                      variant: KasaButtonVariant.primary,
                      fullWidth: false,
                      label: 'ADD',
                      leading: const Icon(Icons.add, size: 14),
                      onTap: () => Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (ctx) => Scaffold(
                            appBar: AppBar(
                              title: const Text('Create Invoice'),
                              leading: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ),
                            body: _CreateInvoiceDialog(
                              onDone: () => ref.invalidate(invoicesProvider),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Filter chips ───────────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  for (final (value, label) in const [
                    ('all', 'ALL'),
                    ('pending', 'PENDING'),
                    ('paid', 'PAID'),
                    ('overdue', 'OVERDUE'),
                  ]) ...[
                    GestureDetector(
                      onTap: () => setState(() => _filter = value),
                      child: KasaChip(
                        label: label,
                        variant: _filter == value
                            ? KasaChipVariant.secondary
                            : KasaChipVariant.neutral,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),

            // ── Invoice list ───────────────────────────────────────────────
            Expanded(
              child: invoices.when(
                loading: () => const SkeletonList(),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(apiError(e),
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref.invalidate(invoicesProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (rawList) {
                  List<dynamic> list = rawList;
                  if (_filter != 'all') {
                    list = list
                        .where((i) =>
                            (i as Map)['status'] == _filter)
                        .toList();
                  }
                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            _filter == 'all'
                                ? 'No invoices yet.'
                                : 'No ${_filter.toUpperCase()} invoices.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          if (_filter == 'all') ...[
                            const SizedBox(height: 4),
                            const Text(
                              'Tap "ADD" to generate the first one.',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(invoicesProvider.future),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final inv = list[i] as Map<String, dynamic>;
                        return _InvoiceCard(
                          invoice: inv,
                          onChanged: () => ref.invalidate(invoicesProvider),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Invoice Card ─────────────────────────────────────────────────────────────

class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({required this.invoice, required this.onChanged});
  final Map<String, dynamic> invoice;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = invoice['status'] as String;
    final balance = double.tryParse((invoice['balance'] ?? '0').toString()) ?? 0;
    final isPaid = status == 'paid';
    final canEdit = status == 'pending' || status == 'overdue';
    final canVoid = status == 'pending' || status == 'overdue';
    final role = ref.watch(userRoleProvider).valueOrNull;
    final isLandlord = role == 'landlord';
    final cs = Theme.of(context).colorScheme;

    // Status chip variant mapping
    final chipVariant = switch (status) {
      'paid'           => KasaChipVariant.primary,
      'overdue'        => KasaChipVariant.tertiary,
      'pending'        => KasaChipVariant.secondary,
      'partially_paid' => KasaChipVariant.secondary,
      _                => KasaChipVariant.neutral,
    };
    final chipLabel = switch (status) {
      'paid'           => 'PAID',
      'overdue'        => 'OVERDUE',
      'pending'        => 'PENDING',
      'partially_paid' => 'PARTIAL',
      'cancelled'      => 'VOID',
      _                => status.replaceAll('_', ' ').toUpperCase(),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KasaCard(
        padding: const EdgeInsets.all(14),
        onTap: () => _showDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row: invoice number + status chip + popup menu
            Row(
              children: [
                Text(
                  invoice['invoice_number'] ?? '',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.kasaTextSub,
                  ),
                ),
                const Spacer(),
                KasaChip(label: chipLabel, variant: chipVariant, small: true),
                if (isLandlord && (!isPaid || canEdit || canVoid))
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 20, color: cs.kasaTextSub),
                    itemBuilder: (_) => [
                      if (!isPaid)
                        const PopupMenuItem(
                          value: 'pay',
                          child: ListTile(
                            leading: Icon(Icons.payments_outlined),
                            title: Text('Record Cash/Bank'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      if (canEdit)
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit Invoice'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      if (canVoid)
                        const PopupMenuItem(
                          value: 'void',
                          child: ListTile(
                            leading: Icon(Icons.cancel_outlined,
                                color: Colors.orange),
                            title: Text('Void Invoice',
                                style: TextStyle(color: Colors.orange)),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                    ],
                    onSelected: (v) {
                      if (v == 'pay') _showRecordPayment(context);
                      if (v == 'edit') _showEdit(context);
                      if (v == 'void') _confirmVoid(context, ref);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Row: tenant · unit
            Text(
              '${invoice['tenant_name'] ?? ''} · Unit ${invoice['unit_number'] ?? ''}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),

            // Row: balance due + record payment arrow
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BALANCE DUE',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.kasaTextSub,
                          letterSpacing: 0.04,
                        ),
                      ),
                      Text(
                        formatCurrency(balance),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isPaid && isLandlord)
                  GestureDetector(
                    onTap: () => _showRecordPayment(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.secondary,
                        borderRadius:
                            BorderRadius.circular(KasaRadius.md),
                        border: Border.all(
                            color: cs.kasaStroke,
                            width: KasaBorders.card),
                        boxShadow: [
                          BoxShadow(
                            color: cs.kasaShadow,
                            offset: const Offset(KasaBorders.shadow,
                                KasaBorders.shadow),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Icon(Icons.arrow_forward,
                          size: 18, color: cs.onSecondary),
                    ),
                  ),
              ],
            ),

            // Due date
            if (invoice['due_date'] != null) ...[
              const SizedBox(height: 6),
              Text(
                'DUE ${_tryFormatDate(invoice['due_date'])}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.kasaTextSub,
                  letterSpacing: 0.04,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InvoiceDetailSheet(
        invoice: invoice,
        onChanged: onChanged,
      ),
    );
  }

  void _showRecordPayment(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _RecordPaymentDialog(
        invoiceId: invoice['id'] as int,
        balance: double.tryParse((invoice['balance'] ?? '0').toString()) ?? 0,
        onDone: onChanged,
      ),
    );
  }

  void _showEdit(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _EditInvoiceDialog(
        invoice: invoice,
        onDone: onChanged,
      ),
    );
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Void Invoice'),
        content: Text(
            'Mark ${invoice['invoice_number']} as cancelled? '
            'No payments or ledger entries will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/api/v1/payments/invoices/${invoice['id']}/cancel/');
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invoice voided.'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  String _tryFormatDate(String raw) {
    try {
      return _displayDate.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }
}

// ─── Invoice Detail Bottom Sheet ──────────────────────────────────────────────

class _InvoiceDetailSheet extends ConsumerStatefulWidget {
  const _InvoiceDetailSheet({required this.invoice, required this.onChanged});
  final Map<String, dynamic> invoice;
  final VoidCallback onChanged;

  @override
  ConsumerState<_InvoiceDetailSheet> createState() => _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends ConsumerState<_InvoiceDetailSheet> {
  bool _stkLoading = false;

  Map<String, dynamic> get invoice => widget.invoice;
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
          backgroundColor: Color(0xFF43A047),
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
              backgroundColor: Color(0xFF43A047),
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                'M-Pesa reported success, but the receipt still needs verification. '
                'Do not pay again; contact your landlord if it remains pending.',
              ),
              backgroundColor: Colors.orange,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Payment status unknown. Refresh invoices to check.'),
        backgroundColor: Colors.orange,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = invoice['status'] as String;
    final isPaid = status == 'paid';
    final canEdit = status == 'pending' || status == 'overdue';
    final canVoid = status == 'pending' || status == 'overdue';
    final payments = invoice['payments'] as List<dynamic>? ?? [];
    final role = ref.watch(userRoleProvider).valueOrNull;
    final isLandlord = role == 'landlord';

    final chipVariant = switch (status) {
      'paid'           => KasaChipVariant.primary,
      'overdue'        => KasaChipVariant.tertiary,
      'pending'        => KasaChipVariant.secondary,
      'partially_paid' => KasaChipVariant.secondary,
      _                => KasaChipVariant.neutral,
    };
    final chipLabel = switch (status) {
      'paid'           => 'PAID',
      'overdue'        => 'OVERDUE',
      'pending'        => 'PENDING',
      'partially_paid' => 'PARTIAL',
      'cancelled'      => 'VOID',
      _                => status.replaceAll('_', ' ').toUpperCase(),
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.kasaBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(KasaRadius.xl)),
          border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header: invoice number + chip
            Row(
              children: [
                Text(
                  invoice['invoice_number'] ?? '',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13, fontWeight: FontWeight.w700, color: cs.kasaTextSub,
                  ),
                ),
                const Spacer(),
                KasaChip(label: chipLabel, variant: chipVariant, small: true),
              ],
            ),
            const SizedBox(height: 8),

            // Hero amount
            Text(
              formatCurrency(toDouble(invoice['amount_due'])),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 40, fontWeight: FontWeight.w700,
                letterSpacing: -1.2, color: cs.onSurface, height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${invoice['tenant_name'] ?? ''} · Unit ${invoice['unit_number'] ?? ''}',
              style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w500, color: cs.kasaTextSub,
              ),
            ),
            const SizedBox(height: 20),

            // Detail rows
            KasaCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _DetailRow('AMOUNT DUE', formatCurrency(toDouble(invoice['amount_due'])), isFirst: true),
                  _DetailRow('AMOUNT PAID', formatCurrency(toDouble(invoice['amount_paid']))),
                  _DetailRow('BALANCE', formatCurrency(toDouble(invoice['balance'])),
                      bold: true,
                      valueColor: isPaid ? cs.statusPaid : cs.error),
                  if (invoice['due_date'] != null)
                    _DetailRow('DUE DATE', _tryFormatDate(invoice['due_date'] as String)),
                  if (invoice['period_start'] != null)
                    _DetailRow(
                      'PERIOD',
                      '${_tryFormatDate(invoice['period_start'] as String)} – '
                          '${_tryFormatDate(invoice['period_end'] as String? ?? '')}',
                    ),
                  if (invoice['notes']?.isNotEmpty == true)
                    _DetailRow('NOTES', invoice['notes'] as String),
                ],
              ),
            ),

            // Line items breakdown
            Builder(builder: (context) {
              final lineItems = invoice['line_items'] as List<dynamic>? ?? [];
              if (lineItems.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'BREAKDOWN',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 0.04, color: cs.kasaTextSub,
                    ),
                  ),
                  const SizedBox(height: 8),
                  KasaCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: lineItems.asMap().entries.map((e) {
                        final i = e.key;
                        final li = e.value as Map<String, dynamic>;
                        final isMetered = li['previous_reading'] != null;
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: i > 0
                                  ? BorderSide(color: cs.kasaStroke, width: 2)
                                  : BorderSide.none,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      li['description'] as String? ?? '',
                                      style: GoogleFonts.inter(
                                        fontSize: 13, fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    if (isMetered) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '${toDouble(li['current_reading']).toStringAsFixed(0)} − '
                                        '${toDouble(li['previous_reading']).toStringAsFixed(0)} = '
                                        '${toDouble(li['units_consumed']).toStringAsFixed(0)} units '
                                        '× ${AppConstants.currency} '
                                        '${toDouble(li['unit_price']).toStringAsFixed(2)}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10, color: cs.kasaTextSub,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Text(
                                formatCurrency(toDouble(li['amount'])),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 13, fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            }),

            const SizedBox(height: 16),

            // Payments
            Text(
              'PAYMENTS (${payments.length})',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 0.04, color: cs.kasaTextSub,
              ),
            ),
            const SizedBox(height: 8),
            if (payments.isEmpty)
              KasaCard(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No payments recorded yet.',
                  style: GoogleFonts.inter(fontSize: 13, color: cs.kasaTextSub),
                ),
              )
            else
              KasaCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: payments.asMap().entries.map((e) {
                    final i = e.key;
                    final pm = e.value as Map<String, dynamic>;
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: i > 0
                              ? BorderSide(color: cs.kasaStroke, width: 2)
                              : BorderSide.none,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cs.kasaStroke, width: 2),
                            ),
                            child: Icon(Icons.check, size: 18, color: cs.onPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatCurrency(toDouble(pm['amount'])),
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14, fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Text(
                                  '${(pm['method_display'] as String? ?? (pm['method'] as String? ?? '')).toUpperCase()} · ${_tryFormatDate(pm['paid_at'] as String? ?? '')}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10, color: cs.kasaTextSub,
                                  ),
                                ),
                                // Bank details
                                if (pm['method'] == 'bank') ...[
                                  if (pm['bank_name'] != null)
                                    Text(
                                      pm['bank_name'] as String,
                                      style: GoogleFonts.inter(
                                        fontSize: 11, color: cs.kasaTextSub,
                                      ),
                                    ),
                                  if (pm['bank_reference'] != null)
                                    Text(
                                      'Ref: ${pm['bank_reference']}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10, color: cs.kasaTextSub,
                                      ),
                                    ),
                                  if (pm['bank_account'] != null)
                                    Text(
                                      'From: ${pm['bank_account']}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10, color: cs.kasaTextSub,
                                      ),
                                    ),
                                  if (pm['bank_branch'] != null)
                                    Text(
                                      'Branch: ${pm['bank_branch']}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10, color: cs.kasaTextSub,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const KasaChip(label: 'PAID', variant: KasaChipVariant.primary, small: true),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 20),

            // Actions
            if (!isPaid)
              KasaButton(
                label: 'PAY WITH MPESA',
                variant: KasaButtonVariant.primary,
                leading: Icon(Icons.phone_android, size: 16, color: cs.onPrimary),
                isLoading: _stkLoading,
                onTap: _stkLoading ? null : () => _showPaymentMethodSheet(context, ref),
              ),
            if (isLandlord) ...[
              if (canEdit) ...[
                const SizedBox(height: 8),
                KasaButton(
                  label: 'EDIT INVOICE',
                  variant: KasaButtonVariant.ghost,
                  leading: Icon(Icons.edit_outlined, size: 16, color: cs.onSurface),
                  onTap: () async {
                    Navigator.pop(context);
                    await Future.delayed(const Duration(milliseconds: 350));
                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      useRootNavigator: true,
                      barrierDismissible: false,
                      builder: (_) => _EditInvoiceDialog(
                        invoice: invoice,
                        onDone: onChanged,
                      ),
                    );
                  },
                ),
              ],
              if (canVoid) ...[
                const SizedBox(height: 8),
                KasaButton(
                  label: 'VOID INVOICE',
                  variant: KasaButtonVariant.ghost,
                  leading: Icon(Icons.cancel_outlined, size: 16, color: cs.tertiary),
                  onTap: () async {
                    Navigator.pop(context);
                    await Future.delayed(const Duration(milliseconds: 350));
                    if (!context.mounted) return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      useRootNavigator: true,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Void Invoice'),
                        content: Text(
                            'Mark ${invoice['invoice_number']} as cancelled? '
                            'No payments or ledger entries will be deleted.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Void'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    try {
                      final dio = ref.read(dioProvider);
                      await dio.post(
                          '/api/v1/payments/invoices/${invoice['id']}/cancel/');
                      onChanged();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Invoice voided.'),
                          backgroundColor: Colors.orange,
                        ));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(apiError(e)),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ));
                      }
                    }
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _tryFormatDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      return _displayDate.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
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

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value,
      {this.isFirst = false, this.bold = false, this.valueColor});
  final String label, value;
  final bool isFirst;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: isFirst
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: cs.kasaStroke, width: 2))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04,
              color: cs.kasaTextSub,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: valueColor ?? cs.onSurface,
              ),
            ),
          ),
        ],
      ),
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
            'PAY INVOICE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22, fontWeight: FontWeight.w700,
              letterSpacing: -0.44, color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Invoice $invoiceNo · Balance ${formatCurrency(balance)}',
            style: GoogleFonts.inter(fontSize: 13, color: cs.kasaTextSub),
          ),
          const SizedBox(height: 20),

          // ── M-Pesa STK Push ───────────────────────────────────────────
          _MethodTile(
            icon: Icons.phone_android_outlined,
            color: const Color(0xFF43A047),
            title: 'M-Pesa (STK Push)',
            subtitle: 'We\'ll send a payment prompt directly to your phone.',
            onTap: onStkPush,
          ),

          const SizedBox(height: 10),

          // ── M-Pesa Paybill (manual) ───────────────────────────────────
          _MethodTile(
            icon: Icons.dialpad_outlined,
            color: const Color(0xFF00897B),
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
              color: const Color(0xFF1565C0),
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
              color: const Color(0xFFF57F17),
              title: 'Cash',
              subtitle: 'Tenant pays in cash. Record when received.',
              onTap: onManualPayment ?? () {},
            ),
          ] else ...[
            const SizedBox(height: 10),
            _MethodTile(
              icon: Icons.payments_outlined,
              color: const Color(0xFFF57F17),
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
                'LIPA NA M-PESA',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w700,
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
                n: 4, label: 'Account No.', value: unitNo),
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
                    style: GoogleFonts.inter(
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
                  'CASH PAYMENT',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, fontWeight: FontWeight.w700,
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
                      style: GoogleFonts.inter(fontSize: 12, color: cs.tertiaryInk),
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
              border: Border.all(color: cs.kasaStroke, width: 2),
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
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    letterSpacing: -0.14, color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub),
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
              border: Border.all(color: cs.kasaStroke, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '$n',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: cs.onSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: text != null
                ? Text(
                    text!,
                    style: GoogleFonts.inter(
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
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 0.04, color: cs.kasaTextSub,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          value ?? '—',
                          style: GoogleFonts.jetBrainsMono(
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
        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
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
                'BANK DETAILS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
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
  List<Map<String, dynamic>> _leases = [];
  bool _initialLoading = true;
  String? _loadError;

  int? _selectedLeaseId;
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
    Future.microtask(_loadLeases);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final item in _lineItems) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLeases() async {
    try {
      final dio = ref.read(dioProvider);
      final raw = await fetchAllPages(
        dio,
        '/api/v1/tenants/leases/',
        queryParameters: {'status': 'active'},
      );
      if (!mounted) return;
      setState(() {
        _leases = raw.cast<Map<String, dynamic>>();
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
          backgroundColor: Colors.orange,
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
    if (_selectedLeaseId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a lease.')));
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
        'lease': _selectedLeaseId,
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
                      // Lease picker
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                            labelText: 'Lease / Tenant *', isDense: true),
                        initialValue: _selectedLeaseId,
                        hint: _leases.isEmpty
                            ? const Text('No active leases')
                            : const Text('Select lease'),
                        isExpanded: true,
                        items: _leases
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
                            _selectedLeaseId = v;
                            for (final item in _lineItems) {
                              item.dispose();
                            }
                            _lineItems = [];
                          });
                          if (v != null) {
                            final lease = _leases.firstWhere(
                                (l) => l['id'] == v, orElse: () => {});
                            if (lease.isNotEmpty) {
                              final rentAmount = double.tryParse(
                                      (lease['rent_amount'] ?? '0')
                                          .toString()) ??
                                  0;
                              _loadPropertyCharges(
                                  rentAmount, lease['property_id'] as int?);
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
                      if (_selectedLeaseId == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text('Select a lease to see charges.',
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
