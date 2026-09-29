import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/api/api_client.dart';
import '../../core/constants.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../dashboard/needs_attention.dart';
import '../tenants/tenants_screen.dart';
import 'meter_readings_screen.dart';
import 'properties_screen.dart';
import 'renumber_units_screen.dart';
import 'unit_numbering.dart';

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

class PropertyDetailScreen extends ConsumerWidget {
  const PropertyDetailScreen({super.key, required this.propertyId});
  final int propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prop = ref.watch(propertyDetailProvider(propertyId));
    final cs = Theme.of(context).colorScheme;

    return prop.when(
      loading: () => Scaffold(
        backgroundColor: cs.kasaBg,
        appBar: AppBar(backgroundColor: cs.kasaBg, elevation: 0),
        body: const KasaSkeletonDetail(),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: cs.kasaBg,
        appBar: AppBar(backgroundColor: cs.kasaBg, elevation: 0),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 56, color: cs.kasaTextSub),
              const SizedBox(height: 12),
              Text(apiError(e), style: KasaFont.sans(color: cs.kasaTextSub)),
              const SizedBox(height: 16),
              KasaButton(
                label: 'Retry',
                variant: KasaButtonVariant.ghost,
                leading: Icon(Icons.refresh, size: 16, color: cs.secondary),
                onTap: () => ref.invalidate(propertyDetailProvider(propertyId)),
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
    );
  }
}

class _PropertyDetailView extends ConsumerStatefulWidget {
  const _PropertyDetailView({
    required this.propertyId,
    required this.data,
    required this.onRefresh,
  });
  final int propertyId;
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_PropertyDetailView> createState() => _PropertyDetailViewState();
}

class _PropertyDetailViewState extends ConsumerState<_PropertyDetailView> {
  String _filter = 'all';

  int get propertyId => widget.propertyId;
  Map<String, dynamic> get data => widget.data;
  VoidCallback get onRefresh => widget.onRefresh;

  /// A caretaker filters by who lives where; only the landlord sees arrears.
  List<(String, String)> _filters(bool isLandlord) => [
        ('all', 'All'),
        if (isLandlord) ('arrears', 'Arrears') else ('occupied', 'Occupied'),
        ('vacant', 'Vacant'),
        ('notice', 'Notice'),
      ];

  /// What a tile shows. The server works this out; a response without it
  /// (an older server) still shows who is vacant.
  static String? _stateOf(Map<String, dynamic> unit) =>
      unit['state'] as String? ?? (unit['status'] == 'vacant' ? 'vacant' : null);

  /// Ground floor first, then up the building; within a floor G1, G2, G10.
  List<Map<String, dynamic>> _sorted(List<dynamic> units) {
    final list = units.cast<Map<String, dynamic>>().toList();
    list.sort((a, b) {
      final byFloor = ((a['floor'] as num?) ?? 0).compareTo((b['floor'] as num?) ?? 0);
      return byFloor != 0
          ? byFloor
          : compareUnitNumbers('${a['unit_number']}', '${b['unit_number']}');
    });
    return list;
  }

  bool _matches(Map<String, dynamic> unit) =>
      _filter == 'all' || _stateOf(unit) == _filter;

  void _addUnit() => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AddUnitDialog(propertyId: propertyId, onDone: onRefresh),
      );

  void _editProperty() => showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => EditPropertyDialog(
          propertyId: propertyId,
          currentName: data['name'] as String? ?? '',
          currentCaretakerId: data['caretaker'] as int?,
          onDone: () {
            ref.invalidate(propertiesProvider);
            onRefresh();
          },
        ),
      );

  Future<void> _deleteProperty() async {
    final gone = await confirmDeleteProperty(
      context,
      ref,
      id: propertyId,
      name: data['name'] as String? ?? 'this property',
    );
    if (gone && mounted) Navigator.of(context).pop();
  }

  /// Add tenant needs a unit to put them in. One vacant unit is used without
  /// asking; several are offered; none says what to do first.
  Future<void> _addTenant(List<Map<String, dynamic>> units) async {
    final vacant = units.where((u) => _stateOf(u) == 'vacant').toList();
    if (vacant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Every unit is occupied. Add a unit first.'),
      ));
      return;
    }
    final unitId = vacant.length == 1
        ? vacant.first['id'] as int
        : await showModalBottomSheet<int>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text('Which unit is the tenant moving into?',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  for (final u in vacant)
                    ListTile(
                      title: Text('Unit ${u['unit_number']}'),
                      subtitle: Text('${formatCurrency(toDouble(u['rent_amount']))}/mo'),
                      onTap: () => Navigator.pop(ctx, u['id'] as int),
                    ),
                ],
              ),
            ),
          );
    if (unitId == null || !mounted) return;
    await startTenancyForUnit(context, ref, unitId);
    onRefresh();
  }

  /// Edit and delete, from a long press on a tile.
  Future<void> _unitActions(Map<String, dynamic> unit) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('Edit unit ${unit['unit_number']}'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('Delete unit ${unit['unit_number']}',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'edit') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => EditUnitDialog(unit: unit, onDone: onRefresh),
      );
    } else {
      await _deleteUnit(unit);
    }
  }

  Future<void> _deleteUnit(Map<String, dynamic> unit) async {
    if (_stateOf(unit) != 'vacant') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only vacant units can be deleted.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete unit?'),
        content: Text('Delete unit ${unit['unit_number']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(dioProvider).delete('/api/v1/properties/units/${unit['id']}/');
      onRefresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiError(e)), backgroundColor: errorColor));
    }
  }

  Future<void> _renumber(List<Map<String, dynamic>> units) async {
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => RenumberUnitsScreen(propertyId: propertyId, units: units),
      ),
    );
    if (changed == true) onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final role = ref.watch(userRoleProvider).valueOrNull;
    final canManage = role == 'landlord';
    // Either of them may walk round and read the meters, and place a tenant.
    final canWork = role == 'landlord' || role == 'caretaker';

    final units = _sorted(data['units'] as List<dynamic>? ?? const []);
    final shown = units.where(_matches).toList();
    int count(String f) =>
        f == 'all' ? units.length : units.where((u) => _stateOf(u) == f).length;
    final occupied = units.where((u) => _stateOf(u) != 'vacant').length;

    final missing = (ref.watch(missingReadingsProvider).valueOrNull ?? const <MissingReadings>[])
        .where((m) => m.propertyId == propertyId)
        .fold<int>(0, (sum, m) => sum + m.missing);

    final place = [
      for (final k in ['address', 'town', 'county'])
        if ('${data[k] ?? ''}'.trim().isNotEmpty) '${data[k]}'.trim(),
    ].take(2).join(', ');
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);

    Widget tool(IconData icon, String title, String? caption, VoidCallback onTap,
            {bool warn = false}) =>
        Expanded(
          child: KasaCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            onTap: onTap,
            child: Row(children: [
              Icon(icon, size: 20, color: cs.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: KasaFont.sans(
                            fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    if (caption != null)
                      Text(caption,
                          style: KasaFont.sans(
                              fontSize: 13, color: warn ? cs.statusDue : cs.kasaTextSub)),
                  ],
                ),
              ),
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Text(data['name'] as String? ?? 'Property',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KasaFont.sans(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
        actions: [
          if (canManage)
            PopupMenuButton<String>(
              tooltip: 'Property options',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) {
                if (v == 'add_unit') _addUnit();
                if (v == 'edit') _editProperty();
                if (v == 'delete') _deleteProperty();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add_unit', child: Text('Add unit')),
                PopupMenuItem(value: 'edit', child: Text('Edit property')),
                PopupMenuItem(value: 'delete', child: Text('Delete property')),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: canWork
          ? KasaActionBar(children: [
              KasaButton(
                label: 'Add tenant',
                variant: KasaButtonVariant.primary,
                leading: Icon(Icons.add_rounded, size: 20, color: cs.onPrimary),
                onTap: () => _addTenant(units),
              ),
            ])
          : null,
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(children: [
              Expanded(child: Text(place, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '$occupied/${units.length}',
                    style: KasaFont.sans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                TextSpan(text: ' occupied', style: muted),
              ])),
            ]),
            const SizedBox(height: 16),
            if (canWork)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  tool(
                    Icons.speed_rounded,
                    'Meter readings',
                    missing > 0 ? '$missing missing' : null,
                    () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => MeterReadingsScreen(
                          propertyId: propertyId,
                          propertyName: data['name']?.toString() ?? '',
                        ),
                      ),
                    ),
                    warn: true,
                  ),
                  if (canManage && units.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    tool(Icons.format_list_numbered_rounded, 'Renumber units', 'G1, 1A \u2026',
                        () => _renumber(units)),
                  ],
                ]),
              ),
            if (canWork) const SizedBox(height: 16),
            if (units.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(children: [
                  Icon(Icons.meeting_room_outlined, size: 56, color: cs.kasaTextSub),
                  const SizedBox(height: 12),
                  Text('No units yet.',
                      style: KasaFont.sans(
                          fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text(canManage ? 'Add the first one to start.' : 'Your landlord has not added any.',
                      style: muted),
                  if (canManage) ...[
                    const SizedBox(height: 16),
                    KasaButton(
                      label: 'Add unit',
                      variant: KasaButtonVariant.secondary,
                      fullWidth: false,
                      onTap: _addUnit,
                    ),
                  ],
                ]),
              )
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (value, label) in _filters(canManage)) ...[
                    KasaFilterPill(
                      label: label,
                      count: count(value),
                      selected: _filter == value,
                      onTap: () => setState(() => _filter = value),
                    ),
                    const SizedBox(width: 8),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('No units match.', textAlign: TextAlign.center, style: muted),
                )
              else
                for (var i = 0; i < shown.length; i += 3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    // Equal heights within a row, and no fixed height to
                    // overflow when the phone's text is set large.
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (var j = 0; j < 3; j++) ...[
                          if (j > 0) const SizedBox(width: 8),
                          Expanded(
                            child: i + j < shown.length
                                ? KasaUnitTile(
                                    number: '${shown[i + j]['unit_number']}',
                                    occupant: '${shown[i + j]['tenant_name'] ?? 'No tenant'}',
                                    state: _stateOf(shown[i + j]),
                                    onTap: () => context.push(
                                        '/properties/$propertyId/units/${shown[i + j]['id']}'),
                                    onLongPress:
                                        canManage ? () => _unitActions(shown[i + j]) : null,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ]),
                    ),
                  ),
              const SizedBox(height: 4),
              Text(
                'Ground floor first. Tap a unit for its tenant, bills and repairs'
                '${canManage ? '; hold to edit or delete.' : '.'}',
                style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Add unit

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
                decoration: const InputDecoration(labelText: 'Unit Number *', hintText: 'e.g. A1, 101'),
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
                    labelText: 'Monthly Rent *', prefixText: '${AppConstants.currency} '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v.replaceAll(',', '')) == null) return 'Invalid';
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
                  if (double.tryParse(v.replaceAll(',', '')) == null) return 'Invalid';
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
                    items: List.generate(20, (i) => DropdownMenuItem(value: i, child: Text('$i'))),
                    onChanged: (v) => setState(() => _floor = v!),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add Unit'),
        ),
      ],
    );
  }
}

// ─── Edit Unit Dialog ─────────────────────────────────────────────────────────

class EditUnitDialog extends ConsumerStatefulWidget {
  const EditUnitDialog({super.key, required this.unit, required this.onDone});
  final Map<String, dynamic> unit;
  final VoidCallback onDone;

  @override
  ConsumerState<EditUnitDialog> createState() => _EditUnitDialogState();
}

class _EditUnitDialogState extends ConsumerState<EditUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _unitNumberCtrl;
  late final TextEditingController _rentCtrl;
  late final TextEditingController _depositCtrl;
  late String _unitType;
  late String _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _unitNumberCtrl = TextEditingController(text: widget.unit['unit_number']?.toString() ?? '');
    _rentCtrl = TextEditingController(text: widget.unit['rent_amount']?.toString() ?? '');
    _depositCtrl = TextEditingController(text: widget.unit['deposit_amount']?.toString() ?? '');
    _unitType = widget.unit['unit_type'] as String? ?? 'bedsitter';
    _status = widget.unit['status'] as String? ?? 'vacant';
  }

  @override
  void dispose() {
    _unitNumberCtrl.dispose();
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).patch('/api/v1/properties/units/${widget.unit['id']}/', data: {
        'unit_number': _unitNumberCtrl.text.trim(),
        'unit_type': _unitType,
        'rent_amount': double.parse(_rentCtrl.text.replaceAll(',', '')),
        'deposit_amount': double.parse(_depositCtrl.text.replaceAll(',', '')),
        'status': _status,
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
      title: Text('Edit Unit ${widget.unit['unit_number']}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _unitNumberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Unit Number',
                  helperText: 'Your own label for this unit, e.g. G1 or 1A',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
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
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'vacant', child: Text('Vacant')),
                  DropdownMenuItem(value: 'occupied', child: Text('Occupied')),
                  DropdownMenuItem(value: 'maintenance', child: Text('Under Maintenance')),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rentCtrl,
                decoration: const InputDecoration(labelText: 'Monthly Rent *', prefixText: '${AppConstants.currency} '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v.replaceAll(',', '')) == null) return 'Invalid';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _depositCtrl,
                decoration: const InputDecoration(labelText: 'Deposit *', prefixText: '${AppConstants.currency} '),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v.replaceAll(',', '')) == null) return 'Invalid';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
