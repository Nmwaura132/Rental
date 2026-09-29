import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_primitives.dart';

final _settlementProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, tenancyId) async {
  final res = await ref
      .watch(dioProvider)
      .get('/api/v1/tenants/tenancies/$tenancyId/settlement/');
  return Map<String, dynamic>.from(res.data);
});

/// The deposit when a tenant moves out: unpaid bills first, then the
/// landlord's deductions, then the refund. Once saved it is a permanent
/// record, and the tenant is sent it itemised.
class DepositSettlementScreen extends ConsumerWidget {
  const DepositSettlementScreen({
    super.key,
    required this.tenancyId,
    required this.tenantName,
  });

  final int tenancyId;
  final String tenantName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_settlementProvider(tenancyId));
    return Scaffold(
      appBar: AppBar(title: Text('Deposit · $tenantName')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiError(e))),
        data: (d) => d['settled'] == true
            ? _Settled(tenancyId: tenancyId, data: d)
            : _Draft(tenancyId: tenancyId, data: d),
      ),
    );
  }
}

// ─── Before settling ─────────────────────────────────────────────────────────

class _Deduction {
  _Deduction(String description)
      : description = TextEditingController(text: description),
        amount = TextEditingController();
  final TextEditingController description;
  final TextEditingController amount;
  double get value => double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
}

class _Draft extends ConsumerStatefulWidget {
  const _Draft({required this.tenancyId, required this.data});
  final int tenancyId;
  final Map<String, dynamic> data;

  @override
  ConsumerState<_Draft> createState() => _DraftState();
}

class _DraftState extends ConsumerState<_Draft> {
  final _deductions = <_Deduction>[];
  final _notes = TextEditingController();
  bool _forfeited = false;
  bool _saving = false;

  static const _suggestions = [
    'Repainting',
    'Repairs',
    'Cleaning',
    'Water, final reading',
  ];

  @override
  void dispose() {
    for (final d in _deductions) {
      d.description.dispose();
      d.amount.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _add(String description) =>
      setState(() => _deductions.add(_Deduction(description)));

  Future<void> _settle(double refund) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle the deposit?'),
        content: Text(
          _forfeited
              ? 'The deposit is kept as forfeited. The tenant is sent the '
                  'statement and your reason. This cannot be changed afterwards.'
              : 'The tenant is sent an itemised statement showing a refund of '
                  '${formatCurrency(refund)}. This cannot be changed afterwards.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Settle')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(dioProvider).post(
        '/api/v1/tenants/tenancies/${widget.tenancyId}/settlement/',
        data: {
          'deductions': [
            for (final d in _deductions)
              if (d.description.text.trim().isNotEmpty || d.value > 0)
                {'description': d.description.text.trim(), 'amount': d.value},
          ],
          'forfeited': _forfeited,
          'notes': _notes.text.trim(),
        },
      );
      ref.invalidate(_settlementProvider(widget.tenancyId));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(apiError(e)), backgroundColor: errorColor));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.data;
    final held = toDouble(d['deposit_held']);
    final arrears = toDouble(d['arrears']);
    final available = toDouble(d['available_after_arrears']);
    final deductions = _deductions.fold<double>(0, (s, x) => s + x.value);
    final refund = _forfeited
        ? 0.0
        : (available - deductions).clamp(0, double.infinity).toDouble();
    final owes = (arrears - held).clamp(0, double.infinity).toDouble() +
        (deductions - available).clamp(0, double.infinity).toDouble();
    final canSettle = d['can_settle'] == true;
    final blankRow = _deductions
        .any((x) => x.description.text.trim().isEmpty || x.value <= 0);
    final needsReason = _forfeited && _notes.text.trim().isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (!canSettle)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: KasaCard(
              accent: KasaCardAccent.tertiary,
              padding: const EdgeInsets.all(12),
              showShadow: false,
              child: Text(
                'The deposit can be settled once the tenant has moved out — '
                'on the last day of their notice or after.',
                style: GoogleFonts.inter(fontSize: 13, color: cs.tertiaryInk),
              ),
            ),
          ),
        _Line('Deposit held', held),
        if (held == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No deposit is recorded as paid on this tenancy.',
              style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub),
            ),
          ),
        if (arrears > 0) _Line('Unpaid bills', -arrears),
        const Divider(height: 24),
        Text('DEDUCTIONS',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.kasaTextSub)),
        const SizedBox(height: 8),
        for (final x in _deductions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: x.description,
                    onChanged: (_) => setState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'For', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: x.amount,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    decoration:
                        const InputDecoration(labelText: 'KES', isDense: true),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _deductions.remove(x)),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              ActionChip(label: Text('+ $s'), onPressed: () => _add(s)),
            ActionChip(label: const Text('+ Other'), onPressed: () => _add('')),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _forfeited,
          onChanged: (v) => setState(() => _forfeited = v),
          title: const Text('Deposit forfeited'),
          subtitle: const Text(
              'The tenant did not vacate before the next payment month'),
        ),
        TextField(
          controller: _notes,
          onChanged: (_) => setState(() {}),
          maxLines: 2,
          decoration: InputDecoration(
            labelText:
                _forfeited ? 'Reason (sent to the tenant)' : 'Notes (optional)',
          ),
        ),
        const Divider(height: 28),
        _Line(_forfeited ? 'Refund (forfeited)' : 'Refund to tenant', refund,
            strong: true),
        if (owes > 0)
          _Line('Tenant still owes', owes, strong: true, warn: true),
        const SizedBox(height: 16),
        KasaButton(
          label: 'SETTLE DEPOSIT',
          variant: KasaButtonVariant.primary,
          isLoading: _saving,
          onTap: (!canSettle || _saving || blankRow || needsReason)
              ? null
              : () => _settle(refund),
        ),
      ],
    );
  }
}

// ─── After settling ──────────────────────────────────────────────────────────

class _Settled extends ConsumerWidget {
  const _Settled({required this.tenancyId, required this.data});
  final int tenancyId;
  final Map<String, dynamic> data;

  Future<void> _recordRefund(BuildContext context, WidgetRef ref) async {
    var method = 'mpesa';
    final reference = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Record the refund'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'mpesa', label: Text('M-Pesa')),
                  ButtonSegment(value: 'bank', label: Text('Bank')),
                  ButtonSegment(value: 'cash', label: Text('Cash')),
                ],
                selected: {method},
                onSelectionChanged: (v) => setLocal(() => method = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (e.g. M-Pesa code)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final ref0 = reference.text.trim();
    reference.dispose();
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(dioProvider).post(
        '/api/v1/tenants/tenancies/$tenancyId/settlement/refund/',
        data: {'method': method, 'reference': ref0},
      );
      ref.invalidate(_settlementProvider(tenancyId));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(apiError(e)), backgroundColor: errorColor));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final refund = toDouble(data['refund_due']);
    final owes = toDouble(data['tenant_owes']);
    final deductions =
        (data['deductions'] as List? ?? []).cast<Map<String, dynamic>>();
    final refundedAt = DateTime.tryParse(data['refunded_at']?.toString() ?? '');
    final settledAt = DateTime.tryParse(data['settled_at']?.toString() ?? '');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (settledAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Settled ${DateFormat('d MMM yyyy').format(settledAt.toLocal())}',
              style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub),
            ),
          ),
        _Line('Deposit held', toDouble(data['deposit_held'])),
        if (toDouble(data['applied_to_arrears']) > 0)
          _Line('Unpaid bills', -toDouble(data['applied_to_arrears'])),
        for (final x in deductions)
          _Line('${x['description']}', -toDouble(x['amount'])),
        const Divider(height: 28),
        if (data['forfeited'] == true) ...[
          const _Line('Refund (forfeited)', 0, strong: true),
          Text('Reason: ${data['notes'] ?? ''}',
              style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub)),
        ] else
          _Line('Refund to tenant', refund, strong: true),
        if (owes > 0)
          _Line('Tenant still owes', owes, strong: true, warn: true),
        const SizedBox(height: 16),
        if (refund > 0 && refundedAt == null)
          KasaButton(
            label: 'RECORD REFUND PAID',
            variant: KasaButtonVariant.primary,
            onTap: () => _recordRefund(context, ref),
          )
        else if (refundedAt != null)
          Text(
            'Refund paid ${DateFormat('d MMM yyyy').format(refundedAt.toLocal())} by '
            '${data['refund_method']}'
            '${(data['refund_reference'] ?? '').toString().isNotEmpty ? ' · ${data['refund_reference']}' : ''}',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount,
      {this.strong = false, this.warn = false});
  final String label;
  final double amount;
  final bool strong;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colour = warn ? cs.error : cs.onSurface;
    final text =
        amount < 0 ? '− ${formatCurrency(-amount)}' : formatCurrency(amount);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.inter(
                  fontSize: strong ? 15 : 14,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                  color: strong ? colour : cs.kasaTextSub,
                )),
          ),
          Text(text,
              style: GoogleFonts.spaceGrotesk(
                fontSize: strong ? 18 : 14,
                fontWeight: FontWeight.w700,
                color: colour,
                fontFeatures: kTabularFigures,
              )),
        ],
      ),
    );
  }
}
