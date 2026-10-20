import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';

/// What a tenant opens the app for: what they owe, what it is made of, and
/// exactly what to pay it to.
class TenantHome extends StatelessWidget {
  const TenantHome({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);
    final unit = data['unit_number'];
    final property = data['property_name'];

    if (unit == null) {
      return const KasaNotice(
        icon: Icons.home_outlined,
        title: 'No home on your account yet',
        body: 'Once your landlord adds you to a unit, your bills and how to pay them show here.',
      );
    }

    final bank = (data['bank_accounts'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final last = (data['last_paid'] as Map?)?.cast<String, dynamic>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Unit $unit · $property', style: muted),
        const SizedBox(height: 12),
        if (data['notice_effective_date'] != null) ...[
          _NoticeBanner(data: data),
          const SizedBox(height: 16),
        ],
        _AmountCard(data: data),
        const SizedBox(height: 24),
        KasaSectionHeader(data['stk_enabled'] == true ? 'Or pay by Paybill' : 'Pay by M-Pesa'),
        const SizedBox(height: 12),
        _PayTo(data: data),
        if (bank.isNotEmpty) ...[
          const SizedBox(height: 24),
          const KasaSectionHeader('Or by bank'),
          const SizedBox(height: 12),
          for (final b in bank) ...[
            KasaListGroup(children: [
              _CopyRow(label: '${b['bank_name']} · ${b['account_name']}', value: '${b['account_number']}'),
            ]),
            const SizedBox(height: 8),
          ],
        ],
        if (last != null) ...[
          const SizedBox(height: 16),
          KasaListGroup(children: [
            KasaListRow(
              leading: const KasaLeadIcon(Icons.check_rounded, tone: KasaStatusKind.paid),
              title: '${_month(last['period_start'])} paid',
              subtitle: [
                formatCurrency(toDouble(last['amount'])),
                if (last['paid_at'] != null) DateFormat('d MMM').format(DateTime.parse('${last['paid_at']}').toLocal()),
              ].join(' · '),
              onTap: () => context.go('/invoices'),
            ),
          ]),
        ],
      ],
    );
  }
}

String _month(dynamic isoDate) =>
    isoDate == null ? '' : DateFormat('MMMM').format(DateTime.parse('$isoDate'));

final _plain = NumberFormat('#,##0');

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bill = (data['current_bill'] as Map?)?.cast<String, dynamic>();
    final owed = toDouble(data['outstanding_balance']);
    final credit = toDouble(data['credit']);
    final openBills = (data['open_bills'] as num?)?.toInt() ?? 0;
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);

    if (bill == null || owed <= 0) {
      return KasaCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Nothing to pay', style: muted)),
            const KasaStatusChip(kind: KasaStatusKind.paid, label: 'Paid up'),
          ]),
          const SizedBox(height: 12),
          Text(formatCurrency(0), style: KasaType.money(40).copyWith(color: cs.onSurface)),
          if (credit > 0) ...[
            const SizedBox(height: 8),
            Text('${formatCurrency(credit)} paid ahead, used on your next bill.', style: muted),
          ],
        ]),
      );
    }

    final due = DateTime.parse('${bill['due_date']}');
    final overdue = bill['status'] == 'overdue';
    final lines = (bill['lines'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final breakdown = [
      for (final l in lines) '${_lineName(l)} ${_plain.format(toDouble(l['amount']))}',
    ].join(' · ');

    return KasaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(openBills > 1 ? 'You owe' : '${_month(bill['period_start'])} bill', style: muted),
          ),
          KasaStatusChip(
            kind: overdue ? KasaStatusKind.overdue : KasaStatusKind.due,
            label: overdue ? 'Overdue' : 'Due ${DateFormat('d MMM').format(due)}',
          ),
        ]),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(formatCurrency(owed), style: KasaType.money(40).copyWith(color: cs.onSurface)),
        ),
        const SizedBox(height: 8),
        if (openBills > 1)
          Text('Across $openBills bills. The oldest is paid first.', style: muted)
        else if (breakdown.isNotEmpty)
          Text(breakdown, style: muted.copyWith(fontFeatures: KasaType.tabular)),
        if (toDouble(bill['amount_paid']) > 0 && openBills <= 1) ...[
          const SizedBox(height: 4),
          Text('${formatCurrency(toDouble(bill['amount_paid']))} of ${formatCurrency(toDouble(bill['amount_due']))} already paid.',
              style: muted),
        ],
      ]),
    );
  }

  static String _lineName(Map<String, dynamic> line) => switch (line['charge_type']) {
        'rent' => 'Rent',
        'deposit' => 'Deposit',
        'water' => 'Water',
        'electricity' => 'Electricity',
        'garbage' => 'Garbage',
        'service' => 'Service',
        'security' => 'Security',
        _ => '${line['description']}',
      };
}

/// The paybill and account (or till) to pay to, each with a Copy button: the
/// two numbers a tenant otherwise has to read off the screen into M-Pesa.
class _PayTo extends StatelessWidget {
  const _PayTo({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final number = '${data['mpesa_paybill'] ?? ''}';
    final account = '${data['pay_account'] ?? ''}';
    if (number.isEmpty) {
      return const KasaNotice(
        icon: Icons.info_outline_rounded,
        title: 'Ask your landlord how to pay',
        body: 'They have not added a paybill or till to Kasa yet.',
      );
    }
    return KasaListGroup(children: [
      if (account.isEmpty)
        _CopyRow(label: 'Till number', value: number)
      else ...[
        _CopyRow(label: 'Paybill', value: number),
        _CopyRow(label: 'Account', value: account),
      ],
    ]);
  }
}

class _CopyRow extends StatefulWidget {
  const _CopyRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  State<_CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<_CopyRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
            const SizedBox(height: 2),
            Text(widget.value,
                style: KasaFont.mono(fontSize: 18, fontWeight: FontWeight.w500, color: cs.onSurface)),
          ]),
        ),
        const SizedBox(width: 8),
        Semantics(
          liveRegion: true,
          child: KasaButton(
            label: _copied ? 'Copied' : 'Copy',
            compact: true,
            fullWidth: false,
            variant: KasaButtonVariant.secondary,
            leading: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 16, color: cs.onSurface),
            onTap: _copy,
          ),
        ),
      ]),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final on = DateFormat('d MMMM yyyy').format(DateTime.parse('${data['notice_effective_date']}'));
    final byLandlord = data['notice_by'] == 'landlord';
    final reason = '${data['notice_reason'] ?? ''}'.trim();
    return KasaNotice(
      icon: Icons.event_outlined,
      tone: byLandlord ? KasaNoticeTone.warn : KasaNoticeTone.info,
      title: byLandlord ? 'Your landlord has given notice' : 'You are moving out',
      body: [
        'Please be out by $on.',
        if (byLandlord && reason.isNotEmpty) 'Reason given: $reason',
      ].join(' '),
    );
  }
}
