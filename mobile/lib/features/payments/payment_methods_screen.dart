import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../shared/widgets/shimmer_loading.dart';

/// The landlord's ways of being paid, as the server holds them.
final paymentAccountsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ref.watch(dioProvider).get('/api/v1/payments/accounts/');
  final data = resp.data;
  final rows = data is Map ? data['results'] as List : data as List;
  return rows.cast<Map<String, dynamic>>();
});

/// One kind of payment method: what it is called, what it is for, and which
/// fields it needs.
class _Kind {
  const _Kind(this.value, this.title, this.blurb, this.icon);
  final String value;
  final String title;
  final String blurb;
  final IconData icon;
}

const _kinds = [
  _Kind('kcb_paybill', 'KCB paybill', 'Payments are recorded on their own once connected.',
      Icons.bolt_rounded),
  _Kind('paybill', 'Other paybill', 'Shown to tenants. You record what arrives.',
      Icons.account_balance_wallet_outlined),
  _Kind('till', 'Till number', 'Buy Goods. Shown to tenants; you record what arrives.',
      Icons.storefront_outlined),
  _Kind('bank', 'Bank account', 'For transfers and deposits at the branch.',
      Icons.account_balance_outlined),
  _Kind('cash', 'Cash', 'You record cash as you receive it.', Icons.payments_outlined),
];

_Kind _kindOf(String? value) => _kinds.firstWhere((k) => k.value == value, orElse: () => _kinds[1]);

/// What a tenant would be told, in one line: "Paybill 899790 · Account 623943#G1".
String describeAccount(Map<String, dynamic> a) {
  final number = '${a['number'] ?? ''}';
  final prefix = '${a['account_prefix'] ?? ''}';
  return switch (a['kind']) {
    'kcb_paybill' || 'paybill' =>
      'Paybill $number · Account ${prefix.isEmpty ? '' : prefix}<house number>',
    'till' => 'Till $number',
    'bank' => '${a['bank_name']} · ${a['account_number']}',
    _ => 'Recorded by you',
  };
}

class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final accounts = ref.watch(paymentAccountsProvider);

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        title: const Text('How tenants pay'),
      ),
      bottomNavigationBar: KasaActionBar(children: [
        KasaButton(
          label: 'Add a payment method',
          leading: Icon(Icons.add_rounded, size: 20, color: cs.onPrimary),
          onTap: () => openPaymentMethodForm(context, ref),
        ),
      ]),
      body: accounts.when(
        loading: () => const SkeletonList(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(apiError(e), style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
              const SizedBox(height: 16),
              KasaButton(
                label: 'Retry',
                variant: KasaButtonVariant.secondary,
                fullWidth: false,
                onTap: () => ref.invalidate(paymentAccountsProvider),
              ),
            ]),
          ),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () => ref.refresh(paymentAccountsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'Tenants see these on their bill and in the app. The first paybill or till '
                'is the one quoted in reminders.',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const KasaNotice(
                  icon: Icons.info_outline_rounded,
                  title: 'No payment method yet',
                  body: 'Add the paybill, till or bank account your tenants should pay into.',
                )
              else
                KasaListGroup(children: [
                  for (final a in rows)
                    KasaListRow(
                      leading: KasaLeadIcon(_kindOf(a['kind'] as String?).icon),
                      title: '${a['kind_display'] ?? _kindOf(a['kind'] as String?).title}',
                      subtitle: describeAccount(a),
                      trailing: a['status'] == 'connecting'
                          ? const KasaStatusChip(kind: KasaStatusKind.due, label: 'Connecting')
                          : null,
                      onTap: () => openPaymentMethodForm(context, ref, existing: a),
                    ),
                ]),
              if (rows.any((a) => a['status'] == 'connecting')) ...[
                const SizedBox(height: 16),
                const KasaNotice(
                  icon: Icons.schedule_rounded,
                  title: 'Connecting your KCB paybill',
                  body: 'We link it with KCB so payments are recorded on their own. Until then, '
                      'tenants can still pay to it and you record what arrives.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Add a payment method, or edit [existing].
Future<void> openPaymentMethodForm(BuildContext context, WidgetRef ref,
    {Map<String, dynamic>? existing}) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PaymentMethodForm(existing: existing),
  ));
  if (saved == true) ref.invalidate(paymentAccountsProvider);
}

class _PaymentMethodForm extends ConsumerStatefulWidget {
  const _PaymentMethodForm({this.existing});
  final Map<String, dynamic>? existing;

  @override
  ConsumerState<_PaymentMethodForm> createState() => _PaymentMethodFormState();
}

class _PaymentMethodFormState extends ConsumerState<_PaymentMethodForm> {
  final _form = GlobalKey<FormState>();
  late String? _kind = widget.existing?['kind'] as String?;
  late final _number = TextEditingController(text: '${widget.existing?['number'] ?? ''}');
  late final _prefix = TextEditingController(text: '${widget.existing?['account_prefix'] ?? ''}');
  late final _bankName = TextEditingController(text: '${widget.existing?['bank_name'] ?? ''}');
  late final _branch = TextEditingController(text: '${widget.existing?['bank_branch'] ?? ''}');
  late final _accountName = TextEditingController(text: '${widget.existing?['account_name'] ?? ''}');
  late final _accountNumber =
      TextEditingController(text: '${widget.existing?['account_number'] ?? ''}');
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_number, _prefix, _bankName, _branch, _accountName, _accountNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _body => {
        'kind': _kind,
        'number': _number.text.trim(),
        'account_prefix': _prefix.text.trim(),
        'bank_name': _bankName.text.trim(),
        'bank_branch': _branch.text.trim(),
        'account_name': _accountName.text.trim(),
        'account_number': _accountNumber.text.trim(),
      };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final dio = ref.read(dioProvider);
      if (_isEdit) {
        await dio.patch('/api/v1/payments/accounts/${widget.existing!['id']}/', data: _body);
      } else {
        await dio.post('/api/v1/payments/accounts/', data: _body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this payment method?'),
        content: const Text('Tenants will no longer be told to pay to it. Payments already '
            'recorded stay as they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).delete('/api/v1/payments/accounts/${widget.existing!['id']}/');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = _kind;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        title: Text(_isEdit ? _kindOf(kind).title : 'Add a payment method'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _busy ? null : _remove,
            ),
        ],
      ),
      bottomNavigationBar: kind == null
          ? null
          : KasaActionBar(children: [
              KasaButton(label: 'Save', isLoading: _busy, onTap: _busy ? null : _save),
            ]),
      body: kind == null ? _kindPicker(cs) : _fields(kind),
    );
  }

  Widget _kindPicker(ColorScheme cs) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('How should tenants pay you?',
              style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
          const SizedBox(height: 12),
          KasaListGroup(children: [
            for (final k in _kinds)
              KasaListRow(
                leading: KasaLeadIcon(k.icon),
                title: k.title,
                subtitle: k.blurb,
                onTap: () => setState(() => _kind = k.value),
              ),
          ]),
        ],
      );

  Widget _fields(String kind) {
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)];
    String? need(String? v, String what) => (v ?? '').trim().isEmpty ? 'Enter the $what' : null;

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (kind == 'kcb_paybill' || kind == 'paybill' || kind == 'till') ...[
            TextFormField(
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: InputDecoration(labelText: kind == 'till' ? 'Till number' : 'Paybill number'),
              validator: (v) => RegExp(r'^\d{5,8}$').hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter the 5 to 8 digit number',
            ),
            if (kind != 'till') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _prefix,
                decoration: const InputDecoration(
                  labelText: 'Before the house number (optional)',
                  hintText: 'e.g. 623943#',
                  helperText: 'If your bank needs your account number first, tenants pay to '
                      '623943#G1. Leave empty if they type the house number alone.',
                  helperMaxLines: 3,
                ),
              ),
            ],
            if (kind == 'kcb_paybill') ...[
              const SizedBox(height: 16),
              const KasaNotice(
                icon: Icons.bolt_rounded,
                title: 'Recorded on its own, once connected',
                body: 'After you save, we link this paybill with KCB. Payments, bank transfers '
                    'and branch deposits then show up in Kasa without you typing them in.',
              ),
            ],
          ],
          if (kind == 'bank') ...[
            TextFormField(
              controller: _bankName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Bank', hintText: 'e.g. KCB'),
              validator: (v) => need(v, 'bank'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accountName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Account name'),
              validator: (v) => need(v, 'account name'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accountNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Account number'),
              validator: (v) => need(v, 'account number'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _branch,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Branch (optional)'),
            ),
          ],
          if (kind == 'cash')
            const KasaNotice(
              icon: Icons.payments_outlined,
              title: 'Cash',
              body: 'Tenants are told they can pay you in cash. Record each payment from the '
                  'Money tab when you receive it.',
            ),
        ],
      ),
    );
  }
}
