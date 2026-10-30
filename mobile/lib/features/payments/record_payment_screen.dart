import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';

const _kenyanBanks = [
  'KCB', 'Equity Bank', 'Co-operative Bank', 'NCBA', 'Absa Kenya',
  'Standard Chartered', 'DTB', 'I&M Bank', 'Family Bank', 'Stanbic',
  'Prime Bank', 'HF Group', 'GT Bank', 'Other',
];

/// Records a payment the landlord has confirmed against one bill.
///
/// M-Pesa comes first because that is how tenants pay the paybill: with no
/// notification from the bank, this is the only way the payment reaches Kasa.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, required this.bill, required this.onDone});
  final Map<String, dynamic> bill;
  final VoidCallback onDone;

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  String _method = 'mpesa';
  late final double _balance = toDouble(widget.bill['balance']);
  late final _amount = TextEditingController(text: _balance.toStringAsFixed(0));
  final _code = TextEditingController();
  String? _bankName;
  final _bankAccount = TextEditingController();
  final _bankReference = TextEditingController();
  final _bankBranch = TextEditingController();
  bool _busy = false;
  String? _amountError;
  String? _referenceError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_amount, _code, _bankAccount, _bankReference, _bankBranch]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isMpesa => _method == 'mpesa';
  bool get _isBank => _method == 'bank';
  double? get _entered => double.tryParse(_amount.text.replaceAll(',', ''));
  String get _firstName => '${widget.bill['tenant_name'] ?? ''}'.split(' ').first;

  Future<void> _save() async {
    final amount = _entered;
    final reference = (_isBank ? _bankReference : _code).text.trim();
    setState(() {
      _error = null;
      _amountError = amount == null || amount <= 0 ? 'Enter the amount paid.' : null;
      _referenceError = !_isMpesa && !_isBank || reference.isNotEmpty
          ? null
          : _isMpesa
              ? 'Enter the code from the M-Pesa message.'
              : 'Enter the reference on the slip.';
    });
    if (_amountError != null || _referenceError != null) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dioProvider).post('/api/v1/payments/record/', data: {
        'invoice': widget.bill['id'],
        'method': _method,
        'amount': amount,
        if (_isMpesa) 'mpesa_receipt_number': reference,
        if (_isBank) ...{
          if (_bankName != null) 'bank_name': _bankName,
          if (_bankAccount.text.trim().isNotEmpty) 'bank_account': _bankAccount.text.trim(),
          'bank_reference': reference,
          if (_bankBranch.text.trim().isNotEmpty) 'bank_branch': _bankBranch.text.trim(),
        },
      });
      widget.onDone();
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Payment recorded. Receipt sent by text.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final over = _isMpesa ? (_entered ?? 0) - _balance : 0.0;
    final figure = KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface);
    return Scaffold(
      appBar: AppBar(title: const Text('Record payment')),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            KasaCard(
              child: Column(children: [
                KasaKeyValue('House', Text('${widget.bill['unit_number']}', style: figure)),
                KasaKeyValue('Tenant', Text('${widget.bill['tenant_name']}', style: figure)),
                KasaKeyValue('Owed on this bill', Text(formatCurrency(_balance), style: figure), strong: true),
              ]),
            ),
            const SizedBox(height: 24),
            const _Heading('How did they pay?'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (value, label) in const [('mpesa', 'M-Pesa'), ('cash', 'Cash'), ('bank', 'Bank')]) ...[
                  KasaFilterPill(
                    label: label,
                    selected: _method == value,
                    onTap: () => setState(() {
                      _method = value;
                      _referenceError = null;
                      _error = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
            const SizedBox(height: 24),
            const _Heading('Amount paid (${AppConstants.currency})'),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
              decoration: InputDecoration(
                errorText: _amountError,
                helperText: over > 0
                    ? '${formatCurrency(over)} over this bill goes to their other bills, then stays as credit.'
                    : null,
                helperMaxLines: 2,
              ),
            ),
            if (_isMpesa) ...[
              const SizedBox(height: 24),
              const _Heading('M-Pesa code'),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
                decoration: InputDecoration(
                  hintText: 'e.g. SIR4K7X2QP',
                  helperText: 'On your M-Pesa statement or the tenant\'s message.',
                  helperMaxLines: 2,
                  errorText: _referenceError,
                ),
              ),
            ],
            if (_isBank) ...[
              const SizedBox(height: 24),
              const _Heading('Reference or slip number'),
              TextField(
                controller: _bankReference,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(hintText: 'e.g. FT25001234567', errorText: _referenceError),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _bankName,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bank'),
                items: [for (final b in _kenyanBanks) DropdownMenuItem(value: b, child: Text(b))],
                onChanged: (v) => setState(() => _bankName = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bankAccount,
                decoration: const InputDecoration(labelText: 'Sender account or phone (optional)'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bankBranch,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Branch (optional)'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              KasaNotice(icon: Icons.error_outline, title: _error!, tone: KasaNoticeTone.bad),
            ],
            const SizedBox(height: 16),
            Text(
              '$_firstName gets a text receipt as soon as you save. A recorded payment can\'t be changed.',
              style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub),
            ),
          ]),
        ),
        KasaActionBar(children: [
          KasaButton(label: 'Record payment', isLoading: _busy, onTap: _busy ? null : _save),
        ]),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
      );
}
