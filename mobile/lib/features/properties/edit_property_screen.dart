import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import 'properties_screen.dart';

String _amountsUrl(Object unitId) => '/api/v1/properties/units/$unitId/set-amounts/';

final _wholeShillings = [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))];

String _shillings(Object? value) => toDouble(value).toStringAsFixed(0);

/// Ask for one house's new rent and deposit and save what changed. True
/// when something was saved.
///
/// The server updates the house and its current tenant together, since bills
/// use the tenant's rent and the move-out refund uses the tenant's deposit.
Future<bool> changeAmounts(BuildContext context, WidgetRef ref, Map<String, dynamic> unit,
    {required bool hasTenant}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ChangeAmountsSheet(
      unit: unit,
      hasTenant: hasTenant,
      onSave: (body) => ref.read(dioProvider).post(_amountsUrl(unit['id']), data: body),
    ),
  );
  return saved == true;
}

class _ChangeAmountsSheet extends StatefulWidget {
  const _ChangeAmountsSheet({required this.unit, required this.hasTenant, required this.onSave});
  final Map<String, dynamic> unit;
  final bool hasTenant;
  final Future<Object?> Function(Map<String, String> body) onSave;

  @override
  State<_ChangeAmountsSheet> createState() => _ChangeAmountsSheetState();
}

class _ChangeAmountsSheetState extends State<_ChangeAmountsSheet> {
  late final _rent = TextEditingController(text: _shillings(widget.unit['rent_amount']));
  late final _deposit = TextEditingController(text: _shillings(widget.unit['deposit_amount']));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rent.dispose();
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, String>{
      if (_rent.text.trim() != _shillings(widget.unit['rent_amount'])) 'rent_amount': _rent.text.trim(),
      if (_deposit.text.trim() != _shillings(widget.unit['deposit_amount'])) 'deposit_amount': _deposit.text.trim(),
    };
    if (body.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(body);
      if (mounted) Navigator.pop(context, true);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.unit['unit_number']}: rent and deposit',
              style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            widget.hasTenant
                ? 'The tenant\'s next bill uses the new rent, and their deposit record is corrected. '
                    'Bills already sent stay as they are.'
                : 'The next tenant is charged these.',
            style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _rent,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: _wholeShillings,
            decoration: const InputDecoration(labelText: 'Monthly rent', prefixText: 'KES '),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _deposit,
            keyboardType: TextInputType.number,
            inputFormatters: _wholeShillings,
            decoration: InputDecoration(labelText: 'Deposit', prefixText: 'KES ', errorText: _error),
            onSubmitted: (_) => _busy ? null : _save(),
          ),
          const SizedBox(height: 16),
          KasaButton(label: 'Save', isLoading: _busy, onTap: _busy ? null : _save),
        ]),
      ),
    );
  }
}

/// A building's details and every house's rent and deposit, on one screen
/// with one Save.
///
/// WHY rents live here: the landlord looks for "edit the building" to fix
/// figures set wrong at setup, and a separate screen was one more place to
/// find. "Set every house to" makes a building-wide change one step.
class EditPropertyScreen extends ConsumerStatefulWidget {
  const EditPropertyScreen({
    super.key,
    required this.propertyId,
    required this.name,
    required this.caretakerId,
    required this.units,
  });
  final int propertyId;
  final String name;
  final int? caretakerId;
  final List<Map<String, dynamic>> units;

  @override
  ConsumerState<EditPropertyScreen> createState() => _EditPropertyScreenState();
}

class _EditPropertyScreenState extends ConsumerState<EditPropertyScreen> {
  late final _name = TextEditingController(text: widget.name);
  late int? _caretakerId = widget.caretakerId;
  List<Map<String, dynamic>> _caretakers = const [];
  bool _caretakersLoading = true;

  late final _rents = {
    for (final u in widget.units) u['id']: TextEditingController(text: _shillings(u['rent_amount'])),
  };
  late final _deposits = {
    for (final u in widget.units) u['id']: TextEditingController(text: _shillings(u['deposit_amount'])),
  };
  final _errors = <Object, String>{};
  final _everyRent = TextEditingController();
  final _everyDeposit = TextEditingController();
  String? _nameError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCaretakers();
  }

  @override
  void dispose() {
    for (final c in [..._rents.values, ..._deposits.values, _everyRent, _everyDeposit, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCaretakers() async {
    try {
      final rows = await fetchAllPages(ref.read(dioProvider), '/api/v1/auth/caretakers/');
      if (!mounted) return;
      setState(() {
        _caretakers = rows.cast<Map<String, dynamic>>();
        // A caretaker since removed from this landlord's list would leave the
        // picker on a value it has no item for, which throws.
        if (!_caretakers.any((c) => c['id'] == _caretakerId)) _caretakerId = null;
        _caretakersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _caretakersLoading = false);
    }
  }

  Future<void> _addCaretaker() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const AddCaretakerDialog(),
    );
    if (created == null) return;
    await _loadCaretakers();
    if (mounted) setState(() => _caretakerId = created['id'] as int?);
  }

  static bool _isAmount(String text) => double.tryParse(text.trim().replaceAll(',', '')) != null;

  bool get _canApply => _isAmount(_everyRent.text) || _isAmount(_everyDeposit.text);

  /// Fills every house's boxes with whichever amounts were typed; nothing is
  /// saved until Save, so a few can still be set differently first.
  void _applyToAll() {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_isAmount(_everyRent.text)) {
        for (final c in _rents.values) {
          c.text = _everyRent.text.trim();
        }
      }
      if (_isAmount(_everyDeposit.text)) {
        for (final c in _deposits.values) {
          c.text = _everyDeposit.text.trim();
        }
      }
    });
  }

  static bool _differs(TextEditingController c, Object? was) {
    final typed = double.tryParse(c.text.replaceAll(',', ''));
    return typed != null && typed != toDouble(was);
  }

  bool _rentChanged(Map<String, dynamic> u) => _differs(_rents[u['id']]!, u['rent_amount']);
  bool _depositChanged(Map<String, dynamic> u) => _differs(_deposits[u['id']]!, u['deposit_amount']);
  bool _changed(Map<String, dynamic> u) => _rentChanged(u) || _depositChanged(u);

  bool get _detailsChanged => _name.text.trim() != widget.name || _caretakerId != widget.caretakerId;

  int get _changeCount => widget.units.where(_changed).length + (_detailsChanged ? 1 : 0);

  String _caretakerName(Map<String, dynamic> c) => '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.trim();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Give the building a name');
      return;
    }
    final changed = widget.units.where(_changed).toList();
    if (changed.isEmpty && !_detailsChanged) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _busy = true;
      _errors.clear();
      _nameError = null;
    });
    final dio = ref.read(dioProvider);
    if (_detailsChanged) {
      try {
        await dio.patch('/api/v1/properties/${widget.propertyId}/', data: {
          'name': _name.text.trim(),
          // Sent even when null, so clearing the picker unassigns.
          'caretaker': _caretakerId,
        });
      } catch (e) {
        _nameError = apiError(e);
      }
    }
    for (final unit in changed) {
      try {
        await dio.post(_amountsUrl(unit['id']), data: {
          if (_rentChanged(unit)) 'rent_amount': _rents[unit['id']]!.text.trim(),
          if (_depositChanged(unit)) 'deposit_amount': _deposits[unit['id']]!.text.trim(),
        });
      } catch (e) {
        _errors[unit['id']] = apiError(e);
      }
    }
    if (!mounted) return;
    if (_errors.isEmpty && _nameError == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  Widget _amountField(TextEditingController c, String label, Object? was, {String? error}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: _wholeShillings,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'KES ',
          errorText: error,
          errorMaxLines: 3,
          helperText: _differs(c, was) ? 'Was ${formatCurrency(toDouble(was))}' : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final heading = KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface);
    final n = _changeCount;
    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(backgroundColor: cs.kasaBg, surfaceTintColor: Colors.transparent, title: const Text('Edit property')),
      // WHY the button in the body: it stays above the keyboard while typing.
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const KasaSectionHeader('Details'),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Building name', errorText: _nameError),
              ),
              const SizedBox(height: 16),
              if (_caretakersLoading)
                const LinearProgressIndicator()
              else
                DropdownButtonFormField<int?>(
                  initialValue: _caretakerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Caretaker'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No caretaker')),
                    for (final c in _caretakers)
                      DropdownMenuItem<int?>(
                        value: c['id'] as int?,
                        child: Text(_caretakerName(c), overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _caretakerId = v),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addCaretaker,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Add a caretaker'),
                ),
              ),
              const SizedBox(height: 24),
              const KasaSectionHeader('Rent and deposit'),
              const SizedBox(height: 4),
              Text(
                'Tenants\' next bills use a new rent, and their deposit records are corrected. '
                'Bills already sent stay as they are.',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
              ),
              const SizedBox(height: 12),
              KasaCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Headings, not floating labels: with a prefix the label was
                  // drawn over the amount once the field lost focus.
                  Text('Set every house to (KES)', style: heading),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextField(
                        controller: _everyRent,
                        keyboardType: TextInputType.number,
                        inputFormatters: _wholeShillings,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(hintText: 'Rent'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _everyDeposit,
                        keyboardType: TextInputType.number,
                        inputFormatters: _wholeShillings,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _canApply ? _applyToAll() : null,
                        decoration: const InputDecoration(hintText: 'Deposit'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Leave either empty to keep each house\'s own.',
                      style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
                  const SizedBox(height: 12),
                  KasaButton(
                    label: 'Apply to all ${widget.units.length}',
                    variant: KasaButtonVariant.secondary,
                    onTap: _canApply ? _applyToAll : null,
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Each house', style: heading),
              for (final unit in widget.units) ...[
                const SizedBox(height: 16),
                Text('${unit['unit_number']}',
                    style: KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _amountField(_rents[unit['id']]!, 'Rent', unit['rent_amount'])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _amountField(_deposits[unit['id']]!, 'Deposit', unit['deposit_amount'],
                        error: _errors[unit['id']]),
                  ),
                ]),
              ],
            ],
          ),
        ),
        KasaActionBar(children: [
          KasaButton(
            label: n == 0 ? 'Save' : 'Save $n ${n == 1 ? 'change' : 'changes'}',
            isLoading: _busy,
            onTap: _busy ? null : _save,
          ),
        ]),
      ]),
    );
  }
}
