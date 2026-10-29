import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';

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

/// Every house in a building with its rent, changed in one go: the fix when
/// a building was set up with one rent and some houses pay another.
class EditRentsScreen extends ConsumerStatefulWidget {
  const EditRentsScreen({super.key, required this.buildingName, required this.units});
  final String buildingName;
  final List<Map<String, dynamic>> units;

  @override
  ConsumerState<EditRentsScreen> createState() => _EditRentsScreenState();
}

class _EditRentsScreenState extends ConsumerState<EditRentsScreen> {
  late final _controllers = {
    for (final u in widget.units) u['id']: TextEditingController(text: toDouble(u['rent_amount']).toStringAsFixed(0)),
  };
  final _errors = <Object, String>{};
  final _everyHouse = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _everyHouse.dispose();
    super.dispose();
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

  Future<void> _save() async {
    final changed = widget.units.where(_changed).toList();
    if (changed.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _busy = true;
      _errors.clear();
    });
    for (final unit in changed) {
      try {
        await ref.read(dioProvider).post(_setRentUrl(unit['id']), data: {
          'rent_amount': _controllers[unit['id']]!.text.trim(),
        });
      } catch (e) {
        _errors[unit['id']] = apiError(e);
      }
    }
    if (!mounted) return;
    if (_errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rent changed for ${changed.length} ${changed.length == 1 ? 'house' : 'houses'}.'),
      ));
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(backgroundColor: cs.kasaBg, surfaceTintColor: Colors.transparent, title: const Text('Edit rents')),
      // WHY the button in the body: it stays above the keyboard while typing.
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                '${widget.buildingName}. Tenants are charged the new rent from their next bill; '
                'bills already sent stay as they are.',
                style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub),
              ),
              const SizedBox(height: 16),
              KasaCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // A heading, not a floating label: with a prefix the label
                  // was drawn over the amount once the field lost focus.
                  Text('Set every house to (KES)',
                      style: KasaFont.sans(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
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
              const SizedBox(height: 24),
              const KasaSectionHeader('Each house'),
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
            label: () {
              final n = widget.units.where(_changed).length;
              return n == 0 ? 'Save' : 'Save $n ${n == 1 ? 'change' : 'changes'}';
            }(),
            isLoading: _busy,
            onTap: _busy ? null : _save,
          ),
        ]),
      ]),
    );
  }
}
