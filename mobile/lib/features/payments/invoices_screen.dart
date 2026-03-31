import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/constants.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../shared/widgets/shimmer_loading.dart';

final _apiDate = DateFormat('yyyy-MM-dd');
final _displayDate = DateFormat('dd MMM yyyy');

final invoicesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/payments/invoices/');
  final data = resp.data;
  if (data is List) return data;
  if (data is Map && data['results'] is List) return data['results'] as List<dynamic>;
  return [];
});

const _statusColor = {
  'paid': Color(0xFF2E7D32),
  'pending': Color(0xFFF57F17),
  'overdue': Color(0xFFB71C1C),
  'partially_paid': Color(0xFF0277BD),
  'cancelled': Color(0xFF546E7A),
};

const _statusBgColor = {
  'paid': Color(0xFFE8F5E9),
  'pending': Color(0xFFFFF8E1),
  'overdue': Color(0xFFFFEBEE),
  'partially_paid': Color(0xFFE1F5FE),
  'cancelled': Color(0xFFECEFF1),
};

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

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final role = ref.watch(userRoleProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      floatingActionButton: role == 'tenant'
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: FloatingActionButton.extended(
                onPressed: () => Navigator.of(context, rootNavigator: true).push(
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
                icon: const Icon(Icons.add),
                label: const Text('Create Invoice'),
              ),
            ),
      body: invoices.when(
        loading: () => const SkeletonList(),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(apiError(e), style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(invoicesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No invoices yet.', style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 4),
                    Text('Tap "Create Invoice" to generate the first one.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(invoicesProvider.future),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final inv = list[i] as Map<String, dynamic>;
                    return _InvoiceCard(
                      invoice: inv,
                      onChanged: () => ref.invalidate(invoicesProvider),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({required this.invoice, required this.onChanged});
  final Map<String, dynamic> invoice;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = invoice['status'] as String;
    final color = _statusColor[status] ?? const Color(0xFF546E7A);
    final bgColor = _statusBgColor[status] ?? const Color(0xFFECEFF1);
    final balance = double.tryParse((invoice['balance'] ?? '0').toString()) ?? 0;
    final isPaid = status == 'paid';
    final canEdit = status == 'pending' || status == 'overdue';
    final canDelete = status == 'pending' || status == 'cancelled';
    final canVoid = status == 'paid' || status == 'partially_paid';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      invoice['invoice_number'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!isPaid || canEdit || canDelete || canVoid)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      itemBuilder: (_) => [
                        if (!isPaid)
                          const PopupMenuItem(
                            value: 'pay',
                            child: ListTile(
                              leading: Icon(Icons.payments_outlined),
                              title: Text('Record Payment'),
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
                              leading: Icon(Icons.cancel_outlined, color: Colors.orange),
                              title: Text('Void Invoice', style: TextStyle(color: Colors.orange)),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                        if (canDelete)
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline, color: Colors.red),
                              title: Text('Delete', style: TextStyle(color: Colors.red)),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                      ],
                      onSelected: (v) {
                        if (v == 'pay') _showRecordPayment(context);
                        if (v == 'edit') _showEdit(context);
                        if (v == 'void') _confirmVoid(context, ref);
                        if (v == 'delete') _confirmDelete(context, ref);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${invoice['tenant_name'] ?? ''} · Unit ${invoice['unit_number'] ?? ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Balance due',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                        Text(
                          formatCurrency(balance),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green : color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isPaid)
                    TextButton.icon(
                      onPressed: () => _showRecordPayment(context),
                      icon: const Icon(Icons.payments, size: 16),
                      label: const Text('Record Payment'),
                    ),
                ],
              ),
              if (invoice['due_date'] != null)
                Text(
                  'Due: ${_tryFormatDate(invoice['due_date'])}',
                  style: TextStyle(
                      fontSize: 11,
                      color: status == 'overdue'
                          ? Colors.red
                          : Colors.grey.shade600),
                ),
            ],
          ),
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text(
            'Delete invoice ${invoice['invoice_number']}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/api/v1/payments/invoices/${invoice['id']}/');
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Invoice deleted.'), backgroundColor: Colors.green),
        );
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

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Void Invoice'),
        content: Text(
            'Mark ${invoice['invoice_number']} as cancelled? '
            'This will reverse the paid status.'),
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
      await dio.patch('/api/v1/payments/invoices/${invoice['id']}/',
          data: {'status': 'cancelled'});
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

class _InvoiceDetailSheet extends ConsumerWidget {
  const _InvoiceDetailSheet({required this.invoice, required this.onChanged});
  final Map<String, dynamic> invoice;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = invoice['status'] as String;
    final color = _statusColor[status] ?? const Color(0xFF546E7A);
    final bgColor = _statusBgColor[status] ?? const Color(0xFFECEFF1);
    final isPaid = status == 'paid';
    final canEdit = status == 'pending' || status == 'overdue';
    final canDelete = status == 'pending' || status == 'cancelled';
    final canVoid = status == 'paid' || status == 'partially_paid';
    final payments = invoice['payments'] as List<dynamic>? ?? [];

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: controller,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(invoice['invoice_number'] ?? '',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            _DetailRow('Tenant', invoice['tenant_name'] ?? ''),
            _DetailRow('Unit', 'Unit ${invoice['unit_number'] ?? ''}'),
            _DetailRow('Amount Due', formatCurrency(toDouble(invoice['amount_due']))),
            _DetailRow('Amount Paid', formatCurrency(toDouble(invoice['amount_paid']))),
            _DetailRow('Balance', formatCurrency(toDouble(invoice['balance'])),
                bold: true,
                color: isPaid ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C)),
            if (invoice['due_date'] != null)
              _DetailRow('Due Date', _tryFormatDate(invoice['due_date'] as String)),
            if (invoice['period_start'] != null)
              _DetailRow(
                'Period',
                '${_tryFormatDate(invoice['period_start'] as String)} – '
                    '${_tryFormatDate(invoice['period_end'] as String? ?? '')}',
              ),
            if (invoice['notes']?.isNotEmpty == true)
              _DetailRow('Notes', invoice['notes'] as String),
            // ── Line Items Breakdown ──
            Builder(builder: (context) {
              final lineItems =
                  invoice['line_items'] as List<dynamic>? ?? [];
              if (lineItems.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 32),
                  const Text('Breakdown',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...lineItems.map((rawItem) {
                    final li = rawItem as Map<String, dynamic>;
                    final isMetered = li['previous_reading'] != null;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(li['description'] as String? ?? ''),
                      subtitle: isMetered
                          ? Text(
                              '${toDouble(li['current_reading']).toStringAsFixed(0)} − '
                              '${toDouble(li['previous_reading']).toStringAsFixed(0)} = '
                              '${toDouble(li['units_consumed']).toStringAsFixed(0)} units '
                              '× ${AppConstants.currency} '
                              '${toDouble(li['unit_price']).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      trailing: Text(formatCurrency(toDouble(li['amount'])),
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 13)),
                    );
                  }),
                ],
              );
            }),
            const Divider(height: 32),
            Text('Payments (${payments.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (payments.isEmpty)
              const Text('No payments recorded yet.',
                  style: TextStyle(color: Colors.grey)),
            ...payments.map((p) {
              final pm = p as Map<String, dynamic>;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(formatCurrency(toDouble(pm['amount']))),
                subtitle: Text(
                    '${(pm['method'] as String).toUpperCase()} · ${_tryFormatDate(pm['paid_at'] as String? ?? '')}'),
              );
            }),
            const SizedBox(height: 20),
            if (!isPaid)
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await Future.delayed(const Duration(milliseconds: 350));
                  if (!context.mounted) return;
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
                },
                icon: const Icon(Icons.payments),
                label: const Text('Record Payment'),
              ),
            if (canEdit) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
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
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Invoice'),
              ),
            ],
            if (canVoid) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                ),
                onPressed: () async {
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
                          'This will reverse the paid status.'),
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
                    await dio.patch(
                        '/api/v1/payments/invoices/${invoice['id']}/',
                        data: {'status': 'cancelled'});
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
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Void Invoice'),
              ),
            ],
            if (canDelete) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await Future.delayed(const Duration(milliseconds: 350));
                  if (!context.mounted) return;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Invoice'),
                      content: Text(
                          'Delete ${invoice['invoice_number']}? This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  try {
                    final dio = ref.read(dioProvider);
                    await dio.delete('/api/v1/payments/invoices/${invoice['id']}/');
                    onChanged();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Invoice deleted.'),
                        backgroundColor: Colors.green,
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
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Invoice'),
              ),
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
  const _DetailRow(this.label, this.value, {this.bold = false, this.color});
  final String label, value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color,
                fontSize: 13,
              ),
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
  bool _loading = false;

  static const _methods = [
    ('cash', 'Cash'),
    ('bank', 'Bank Transfer'),
    ('mpesa', 'M-Pesa'),
    ('airtel', 'Airtel Money'),
    ('card', 'Card'),
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
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount.')),
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
    return AlertDialog(
      title: const Text('Record Payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Payment Method'),
            items: _methods
                .map((m) =>
                    DropdownMenuItem(value: m.$1, child: Text(m.$2)))
                .toList(),
            onChanged: (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
                labelText: 'Amount (${AppConstants.currency})', prefixText: '${AppConstants.currency} '),
            keyboardType: TextInputType.number,
          ),
        ],
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
      final resp = await dio.get(
        '/api/v1/tenants/leases/',
        queryParameters: {'status': 'active'},
      );
      if (!mounted) return;
      final data = resp.data;
      List<dynamic> raw;
      if (data is List) {
        raw = data;
      } else if (data is Map && data['results'] is List) {
        raw = data['results'] as List<dynamic>;
      } else {
        raw = [];
      }
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
        final resp = await dio.get(
          '/api/v1/properties/charges/',
          queryParameters: {'property': propertyId, 'is_active': 'true'},
        );
        final data = resp.data;
        if (data is List) {
          charges = data.cast<Map<String, dynamic>>();
        } else if (data is Map && data['results'] is List) {
          charges = (data['results'] as List).cast<Map<String, dynamic>>();
        }
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
