import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/constants.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';

final propertyDetailProvider =
    FutureProvider.family.autoDispose<Map<String, dynamic>, int>((ref, id) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/properties/$id/');
  return resp.data as Map<String, dynamic>;
});

const _unitTypeLabels = {
  'bedsitter': 'Bedsitter',
  '1bed': '1 Bedroom',
  '2bed': '2 Bedroom',
  '3bed': '3 Bedroom',
  'studio': 'Studio',
  'commercial': 'Commercial',
};

const _statusColors = {
  'vacant': Colors.green,
  'occupied': Colors.blue,
  'maintenance': Colors.orange,
};

class PropertyDetailScreen extends ConsumerWidget {
  const PropertyDetailScreen({super.key, required this.propertyId});
  final int propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prop = ref.watch(propertyDetailProvider(propertyId));

    return Scaffold(
      body: prop.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
                const SizedBox(height: 12),
                Text(apiError(e), style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(propertyDetailProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (data) => _PropertyDetailView(
          propertyId: propertyId,
          data: data,
          onRefresh: () => ref.invalidate(propertyDetailProvider(propertyId)),
        ),
      ),
    );
  }
}

class _PropertyDetailView extends ConsumerWidget {
  const _PropertyDetailView({
    required this.propertyId,
    required this.data,
    required this.onRefresh,
  });
  final int propertyId;
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = (data['units'] as List<dynamic>? ?? []);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(data['name'] ?? 'Property'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => _AddUnitDialog(propertyId: propertyId, onDone: onRefresh),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add Unit'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Property info card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.location_on,
                                  size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: Text(data['address'] ?? '',
                                      style: theme.textTheme.bodyMedium)),
                            ]),
                            const SizedBox(height: 4),
                            Text('${data['town']}, ${data['county']}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey)),
                            const SizedBox(height: 12),
                            Row(children: [
                              _InfoChip(
                                label: '${data['unit_count']} units',
                                icon: Icons.meeting_room,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              _InfoChip(
                                label: '${data['vacant_count']} vacant',
                                icon: Icons.door_front_door,
                                color: data['vacant_count'] > 0
                                    ? Colors.orange
                                    : Colors.green,
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Units', style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (units.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.meeting_room_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No units yet.', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 4),
                      Text('Tap "Add Unit" to add the first unit.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final u = units[i] as Map<String, dynamic>;
                      final status = u['status'] as String;
                      final color = _statusColors[status] ?? Colors.grey;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Icon(Icons.meeting_room, color: color),
                          ),
                          title: Text('Unit ${u['unit_number']}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${_unitTypeLabels[u['unit_type']] ?? u['unit_type']}  ·  Floor ${u['floor']}\n${formatCurrency(toDouble(u['rent_amount']))}'),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => _EditUnitDialog(
                                    unit: u,
                                    onDone: onRefresh,
                                  ),
                                );
                              } else if (action == 'delete') {
                                if (status != 'vacant') {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Only vacant units can be deleted.'),
                                    ),
                                  );
                                  return;
                                }
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Unit'),
                                    content: Text('Delete Unit ${u['unit_number']}?'),
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
                                    await ref.read(dioProvider).delete(
                                        '/api/v1/properties/units/${u['id']}/');
                                    onRefresh();
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text('Delete failed: $e'),
                                        backgroundColor: Theme.of(context).colorScheme.error,
                                      ));
                                    }
                                  }
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Edit'))),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                      leading: Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      title: Text('Delete',
                                          style: TextStyle(color: Colors.red)))),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: units.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ─── Add Unit Dialog ──────────────────────────────────────────────────────────

class _AddUnitDialog extends ConsumerStatefulWidget {
  const _AddUnitDialog({required this.propertyId, required this.onDone});
  final int propertyId;
  final VoidCallback onDone;

  @override
  ConsumerState<_AddUnitDialog> createState() => _AddUnitDialogState();
}

class _AddUnitDialogState extends ConsumerState<_AddUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _numberCtrl = TextEditingController();
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  String _unitType = 'bedsitter';
  int _floor = 0;
  bool _loading = false;

  @override
  void dispose() {
    _numberCtrl.dispose();
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/api/v1/properties/units/', data: {
        'property': widget.propertyId,
        'unit_number': _numberCtrl.text.trim(),
        'unit_type': _unitType,
        'rent_amount': double.parse(_rentCtrl.text.replaceAll(',', '')),
        'deposit_amount': double.parse(_depositCtrl.text.replaceAll(',', '')),
        'floor': _floor,
      });
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
      title: const Text('Add Unit'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _numberCtrl,
                decoration: const InputDecoration(
                    labelText: 'Unit Number *', hintText: 'e.g. A1, 101'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _unitType,
                decoration: const InputDecoration(labelText: 'Unit Type'),
                items: _unitTypeLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _unitType = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rentCtrl,
                decoration: const InputDecoration(
                    labelText: 'Monthly Rent (${AppConstants.currency}) *', prefixText: '${AppConstants.currency} '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v.replaceAll(',', '')) == null) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _depositCtrl,
                decoration: const InputDecoration(
                    labelText: 'Deposit Amount (${AppConstants.currency}) *', prefixText: '${AppConstants.currency} '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v.replaceAll(',', '')) == null) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Floor: '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _floor,
                    items: List.generate(
                      20,
                      (i) => DropdownMenuItem(value: i, child: Text('$i')),
                    ),
                    onChanged: (v) => setState(() => _floor = v!),
                  ),
                ],
              ),
            ],
          ),
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
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add Unit'),
        ),
      ],
    );
  }
}

// ─── Edit Unit Dialog ─────────────────────────────────────────────────────────

class _EditUnitDialog extends ConsumerStatefulWidget {
  const _EditUnitDialog({required this.unit, required this.onDone});
  final Map<String, dynamic> unit;
  final VoidCallback onDone;

  @override
  ConsumerState<_EditUnitDialog> createState() => _EditUnitDialogState();
}

class _EditUnitDialogState extends ConsumerState<_EditUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rentCtrl;
  late final TextEditingController _depositCtrl;
  late String _unitType;
  late String _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _rentCtrl = TextEditingController(
        text: widget.unit['rent_amount']?.toString() ?? '');
    _depositCtrl = TextEditingController(
        text: widget.unit['deposit_amount']?.toString() ?? '');
    _unitType = widget.unit['unit_type'] as String? ?? 'bedsitter';
    _status = widget.unit['status'] as String? ?? 'vacant';
  }

  @override
  void dispose() {
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).patch(
        '/api/v1/properties/units/${widget.unit['id']}/',
        data: {
          'unit_type': _unitType,
          'rent_amount': double.parse(_rentCtrl.text.replaceAll(',', '')),
          'deposit_amount':
              double.parse(_depositCtrl.text.replaceAll(',', '')),
          'status': _status,
        },
      );
      widget.onDone();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Update failed: $e'),
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
      title: Text('Edit Unit ${widget.unit['unit_number']}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _unitType,
                decoration: const InputDecoration(labelText: 'Unit Type'),
                items: _unitTypeLabels.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _unitType = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'vacant', child: Text('Vacant')),
                  DropdownMenuItem(
                      value: 'occupied', child: Text('Occupied')),
                  DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('Under Maintenance')),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rentCtrl,
                decoration: const InputDecoration(
                    labelText: 'Monthly Rent *', prefixText: '${AppConstants.currency} '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v.replaceAll(',', '')) == null) {
                    return 'Invalid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _depositCtrl,
                decoration: const InputDecoration(
                    labelText: 'Deposit *', prefixText: '${AppConstants.currency} '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v.replaceAll(',', '')) == null) {
                    return 'Invalid';
                  }
                  return null;
                },
              ),
            ],
          ),
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
