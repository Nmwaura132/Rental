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

String _setRentUrl(Object unitId) => '/api/v1/properties/units/$unitId/set-rent/';

final _wholeShillings = [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))];

/// Ask for one house's new rent and save it. True when it changed.
///
/// The server updates the house and its current tenant together, since bills
/// are worked out from the tenant's rent.
Future<bool> changeRent(BuildContext context, WidgetRef ref, Map<String, dynamic> unit,
    {required bool hasTenant}) async {
  final controller = TextEditingController(text: toDouble(unit['rent_amount']).toStringAsFixed(0));
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ChangeRentSheet(
      unit: unit,
      hasTenant: hasTenant,
      controller: controller,
      onSave: (amount) => ref.read(dioProvider).post(_setRentUrl(unit['id']), data: {'rent_amount': amount}),
    ),
  );
  controller.dispose();
  return saved == true;
}

class _ChangeRentSheet extends StatefulWidget {
  const _ChangeRentSheet({required this.unit, required this.hasTenant, required this.controller, required this.onSave});
  final Map<String, dynamic> unit;
  final bool hasTenant;
  final TextEditingController controller;
  final Future<Object?> Function(String amount) onSave;

  @override
  State<_ChangeRentSheet> createState() => _ChangeRentSheetState();
}

class _ChangeRentSheetState extends State<_ChangeRentSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(widget.controller.text.trim());
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
          Text('Rent for ${widget.unit['unit_number']}',
              style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            widget.hasTenant
                ? 'The tenant is charged this from their next bill. Bills already sent stay as they are.'
                : 'The next tenant is charged this.',
            style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: _wholeShillings,
            decoration: InputDecoration(labelText: 'Monthly rent', prefixText: 'KES ', errorText: _error),
            onSubmitted: (_) => _busy ? null : _save(),
          ),
          const SizedBox(height: 16),
          KasaButton(label: 'Save', isLoading: _busy, onTap: _busy ? null : _save),
        ]),
      ),
    );
  }
}

/// A building's details and every house's rent, on one screen with one Save.
///
/// WHY rents live here: the landlord looks for "edit the building" to fix a
/// rent set wrong at setup, and a separate rents screen was one more place to
/// find. The rent part keeps "Set every house to" for a building-wide change.
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

  late final _controllers = {
    for (final u in widget.units) u['id']: TextEditingController(text: toDouble(u['rent_amount']).toStringAsFixed(0)),
  };
  final _errors = <Object, String>{};
  final _everyHouse = TextEditingController();
  String? _nameError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCaretakers();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _everyHouse.dispose();
    _name.dispose();
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

  /// Fills every house's box; nothing is saved until Save, so a few can
  /// still be set differently first.
  void _applyToAll() {
    final amount = _everyHouse.text.trim();
    if (double.tryParse(amount.replaceAll(',', '')) == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      for (final c in _controllers.values) {
        c.text = amount;
      }
    });
  }

  bool _changed(Map<String, dynamic> unit) {
    final typed = double.tryParse(_controllers[unit['id']]!.text.replaceAll(',', ''));
    return typed != null && typed != toDouble(unit['rent_amount']);
  }

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
        await dio.post(_setRentUrl(unit['id']), data: {'rent_amount': _controllers[unit['id']]!.text.trim()});
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
              const KasaSectionHeader('Rents'),
              const SizedBox(height: 4),
              Text(
                'Tenants are charged a new rent from their next bill; bills already sent stay as they are.',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
              ),
              const SizedBox(height: 12),
              KasaCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // A heading, not a floating label: with a prefix the label
                  // was drawn over the amount once the field lost focus.
                  Text('Set every house to (KES)', style: heading),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _everyHouse,
                    keyboardType: TextInputType.number,
                    inputFormatters: _wholeShillings,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _applyToAll(),
                    decoration: const InputDecoration(hintText: 'e.g. 3000'),
                  ),
                  const SizedBox(height: 12),
                  KasaButton(
                    label: 'Apply to all ${widget.units.length}',
                    variant: KasaButtonVariant.secondary,
                    onTap: double.tryParse(_everyHouse.text.replaceAll(',', '')) == null ? null : _applyToAll,
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Each house', style: heading),
              const SizedBox(height: 12),
              for (final unit in widget.units) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 64,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text('${unit['unit_number']}',
                          style: KasaFont.sans(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controllers[unit['id']],
                      keyboardType: TextInputType.number,
                      inputFormatters: _wholeShillings,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: 'KES ',
                        errorText: _errors[unit['id']],
                        helperText: _changed(unit) ? 'Was ${formatCurrency(toDouble(unit['rent_amount']))}' : null,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
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
