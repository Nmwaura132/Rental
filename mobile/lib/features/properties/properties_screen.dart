import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/constants.dart';
import '../../core/utils/api_error.dart';
import '../../shared/widgets/shimmer_loading.dart';

final propertiesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/properties/');
  final data = resp.data;
  if (data is List) return data;
  if (data is Map && data['results'] is List) return data['results'] as List<dynamic>;
  return [];
});

class PropertiesScreen extends ConsumerWidget {
  const PropertiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final props = ref.watch(propertiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Properties')),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (ctx) => Scaffold(
                appBar: AppBar(
                  title: const Text('Add Property'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                body: _AddPropertyPage(
                  onDone: () => ref.invalidate(propertiesProvider),
                ),
              ),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add Property'),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: props.when(
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
                  onPressed: () => ref.invalidate(propertiesProvider),
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
                      Icon(Icons.home_work_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No properties yet.', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text('Tap "Add Property" to get started.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i] as Map<String, dynamic>;
                    final unitCount = p['unit_count'] as int? ?? 0;
                    final vacantCount = p['vacant_count'] as int? ?? 0;
                    final occupiedCount = unitCount - vacantCount;
                    return Card(
                      child: ListTile(
                        leading: Hero(
                          tag: 'property_avatar_${p['id']}',
                          child: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(Icons.home_work,
                                color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                        ),
                        title: Text(p['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '$unitCount unit${unitCount == 1 ? '' : 's'}'
                          '  ·  $occupiedCount occupied'
                          '  ·  $vacantCount vacant',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'open') {
                              context.go('/properties/${p['id']}');
                            } else if (action == 'edit') {
                              await showDialog(
                                context: context,
                                useRootNavigator: true,
                                barrierDismissible: false,
                                builder: (_) => _EditPropertyDialog(
                                  propertyId: p['id'] as int,
                                  currentName: p['name'] as String,
                                  onDone: () => ref.invalidate(propertiesProvider),
                                ),
                              );
                            } else if (action == 'delete') {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                useRootNavigator: true,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Property'),
                                  content: Text(
                                      'Delete "${p['name']}"? This will also delete all its units and data.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(ctx).colorScheme.error,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && context.mounted) {
                                try {
                                  await ref.read(dioProvider).delete('/api/v1/properties/${p['id']}/');
                                  ref.invalidate(propertiesProvider);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(apiError(e)),
                                      backgroundColor: Theme.of(context).colorScheme.error,
                                    ));
                                  }
                                }
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Open'))),
                            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)))),
                          ],
                        ),
                        onTap: () => context.go('/properties/${p['id']}'),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

// ─── Charge Item (mutable config for one charge type) ─────────────────────────

class _ChargeItem {
  final String type;
  final String label;
  bool enabled = false;
  String billingMethod;
  final TextEditingController priceCtrl;

  _ChargeItem({
    required this.type,
    required this.label,
    this.billingMethod = 'flat',
  }) : priceCtrl = TextEditingController();

  void dispose() => priceCtrl.dispose();
}

// ─── Add Property Page (full-screen) ──────────────────────────────────────────

const _unitTypeLabels = {
  'bedsitter': 'Bedsitter',
  '1bed': '1 Bedroom',
  '2bed': '2 Bedroom',
  '3bed': '3 Bedroom',
  'studio': 'Studio',
  'commercial': 'Commercial',
};

class _AddPropertyPage extends ConsumerStatefulWidget {
  const _AddPropertyPage({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_AddPropertyPage> createState() => _AddPropertyPageState();
}

class _AddPropertyPageState extends ConsumerState<_AddPropertyPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();

  int _numFloors = 1;
  int _unitsPerFloor = 1;
  String _unitType = 'bedsitter';
  bool _loading = false;
  int _createdUnits = 0;
  int _totalUnits = 0;

  late final List<_ChargeItem> _charges;

  @override
  void initState() {
    super.initState();
    _charges = [
      _ChargeItem(type: 'water', label: 'Water', billingMethod: 'metered'),
      _ChargeItem(type: 'electricity', label: 'Electricity', billingMethod: 'metered'),
      _ChargeItem(type: 'garbage', label: 'Garbage / Refuse'),
      _ChargeItem(type: 'service', label: 'Service Charge'),
      _ChargeItem(type: 'security', label: 'Security'),
      _ChargeItem(type: 'sewer', label: 'Sewerage'),
    ];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    for (final c in _charges) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _buildUnits(int propertyId) {
    final units = <Map<String, dynamic>>[];
    final rent = double.tryParse(_rentCtrl.text.replaceAll(',', '')) ?? 0;
    final deposit = double.tryParse(_depositCtrl.text.replaceAll(',', '')) ?? 0;
    for (int floor = 1; floor <= _numFloors; floor++) {
      for (int unit = 1; unit <= _unitsPerFloor; unit++) {
        units.add({
          'property': propertyId,
          'unit_number': '${floor}0$unit'.padLeft(3, '0').replaceAll(' ', ''),
          'unit_type': _unitType,
          'rent_amount': rent,
          'deposit_amount': deposit,
          'floor': floor - 1,
        });
      }
    }
    return units;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _totalUnits = _numFloors * _unitsPerFloor;
      _createdUnits = 0;
    });

    try {
      final dio = ref.read(dioProvider);

      final propResp = await dio.post('/api/v1/properties/', data: {
        'name': _nameCtrl.text.trim(),
      });
      final propertyId = propResp.data['id'] as int;

      final units = _buildUnits(propertyId);
      for (final unit in units) {
        await dio.post('/api/v1/properties/units/', data: unit);
        if (mounted) setState(() => _createdUnits++);
      }

      for (final c in _charges.where((c) => c.enabled)) {
        await dio.post('/api/v1/properties/charges/', data: {
          'property': propertyId,
          'charge_type': c.type,
          'name': c.label,
          'billing_method': c.billingMethod,
          'unit_price': double.tryParse(c.priceCtrl.text) ?? 0,
        });
      }

      widget.onDone();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Property created with ${units.length} unit${units.length == 1 ? '' : 's'}.'),
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

  Widget _buildChargeRow(_ChargeItem charge) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          value: charge.enabled,
          onChanged: _loading ? null : (v) => setState(() => charge.enabled = v!),
          title: Text(charge.label),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (charge.enabled)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 8, right: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: charge.billingMethod,
                  decoration: const InputDecoration(
                    labelText: 'Billing method',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'flat', child: Text('Flat fee')),
                    DropdownMenuItem(value: 'metered', child: Text('Per unit (metered)')),
                  ],
                  onChanged: (v) => setState(() => charge.billingMethod = v!),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: charge.priceCtrl,
                  decoration: InputDecoration(
                    labelText: charge.billingMethod == 'metered'
                        ? 'Price per unit'
                        : 'Amount',
                    prefixText: '${AppConstants.currency} ',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (!charge.enabled) return null;
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v.trim()) == null) return 'Invalid';
                    return null;
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalUnits = _numFloors * _unitsPerFloor;

    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Property name
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Property Name *',
                      hintText: 'e.g. Sunset Apartments',
                      prefixIcon: Icon(Icons.home_work),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),

                  // Layout
                  Text('Layout', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _CounterField(
                          label: 'Floors',
                          value: _numFloors,
                          min: 1,
                          max: 50,
                          onChanged: (v) => setState(() => _numFloors = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CounterField(
                          label: 'Units/Floor',
                          value: _unitsPerFloor,
                          min: 1,
                          max: 50,
                          onChanged: (v) => setState(() => _unitsPerFloor = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Will create $totalUnits unit${totalUnits == 1 ? '' : 's'} total',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),

                  // Unit type
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _unitType,
                    decoration: const InputDecoration(labelText: 'Unit Type'),
                    items: _unitTypeLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _unitType = v!),
                  ),
                  const SizedBox(height: 12),

                  // Rent & deposit
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _rentCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Monthly Rent *',
                            prefixText: '${AppConstants.currency} ',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v!.isEmpty) return 'Required';
                            if (double.tryParse(v.replaceAll(',', '')) == null) return 'Invalid';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _depositCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Deposit *',
                            prefixText: '${AppConstants.currency} ',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v!.isEmpty) return 'Required';
                            if (double.tryParse(v.replaceAll(',', '')) == null) return 'Invalid';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),

                  // ── Additional Charges ────────────────────────────────────
                  const SizedBox(height: 28),
                  Text('Additional Charges', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Select charges that apply to this property. '
                    'These will appear on tenant invoices.',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                  const SizedBox(height: 8),
                  ..._charges.map(_buildChargeRow),
                ],
              ),
            ),
          ),
        ),

        // Bottom action bar
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              if (_loading && _totalUnits > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                          value: _totalUnits > 0 ? _createdUnits / _totalUnits : null),
                      const SizedBox(height: 4),
                      Text(
                        'Creating units: $_createdUnits / $_totalUnits',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(120, 48)),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Property'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Counter Field ─────────────────────────────────────────────────────────────

class _CounterField extends StatelessWidget {
  const _CounterField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: value > min ? () => onChanged(value - 1) : null,
                child: Icon(Icons.remove_circle_outline,
                    size: 22,
                    color: value > min ? theme.colorScheme.primary : theme.disabledColor),
              ),
              Text('$value',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: value < max ? () => onChanged(value + 1) : null,
                child: Icon(Icons.add_circle_outline,
                    size: 22,
                    color: value < max ? theme.colorScheme.primary : theme.disabledColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Edit Property Dialog ─────────────────────────────────────────────────────

class _EditPropertyDialog extends ConsumerStatefulWidget {
  const _EditPropertyDialog({
    required this.propertyId,
    required this.currentName,
    required this.onDone,
  });
  final int propertyId;
  final String currentName;
  final VoidCallback onDone;

  @override
  ConsumerState<_EditPropertyDialog> createState() => _EditPropertyDialogState();
}

class _EditPropertyDialogState extends ConsumerState<_EditPropertyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).patch(
        '/api/v1/properties/${widget.propertyId}/',
        data: {'name': _nameCtrl.text.trim()},
      );
      widget.onDone();
      if (mounted) Navigator.pop(context);
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
      title: const Text('Edit Property'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Property Name *',
            prefixIcon: Icon(Icons.home_work),
          ),
          textCapitalization: TextCapitalization.words,
          validator: (v) => v!.trim().isEmpty ? 'Required' : null,
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
