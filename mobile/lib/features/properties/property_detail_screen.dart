import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api/api_client.dart';
import '../../core/constants.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/kasa_primitives.dart';

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
        body: const Center(child: CircularProgressIndicator()),
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
              Text(apiError(e), style: GoogleFonts.inter(color: cs.kasaTextSub)),
              const SizedBox(height: 16),
              KasaButton(
                label: 'RETRY',
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
    final cs = Theme.of(context).colorScheme;
    final unitCount = data['unit_count'] as int? ?? units.length;
    final vacantCount = data['vacant_count'] as int? ?? 0;
    final occupiedCount = unitCount - vacantCount;
    final canManage = ref.watch(userRoleProvider).valueOrNull == 'landlord';

    return Scaffold(
      backgroundColor: cs.kasaBg,
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: CustomScrollView(
          slivers: [
            // ── App bar ────────────────────────────────────────────────────
            SliverAppBar(
              backgroundColor: cs.kasaBg,
              pinned: true,
              elevation: 0,
              leading: IconButton(
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.kasaCard,
                    borderRadius: BorderRadius.circular(KasaRadius.sm),
                    border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                    boxShadow: [
                      BoxShadow(color: cs.kasaShadow, offset: const Offset(3, 3), blurRadius: 0),
                    ],
                  ),
                  child: Icon(Icons.arrow_back, size: 18, color: cs.onSurface),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: canManage ? [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: KasaButton(
                    label: 'ADD UNIT',
                    variant: KasaButtonVariant.primary,
                    fullWidth: false,
                    leading: Icon(Icons.add, size: 14, color: cs.onPrimary),
                    onTap: () => showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _AddUnitDialog(propertyId: propertyId, onDone: onRefresh),
                    ),
                  ),
                ),
              ] : null,
            ),

            // ── Property summary card ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: KasaCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: cs.secondary,
                              borderRadius: BorderRadius.circular(KasaRadius.md),
                              border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                            ),
                            child: Icon(Icons.home_work, size: 26, color: cs.onSecondary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (data['name'] as String? ?? 'Property').toUpperCase(),
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 20, fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4, color: cs.onSurface, height: 1,
                                  ),
                                ),
                                if ((data['address'] as String? ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    data['address'] as String,
                                    style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // KPI row
                      Row(
                        children: [
                          _KpiTile(label: 'TOTAL', value: '$unitCount', accent: KasaCardAccent.elevated),
                          const SizedBox(width: 10),
                          _KpiTile(label: 'OCCUPIED', value: '$occupiedCount', accent: KasaCardAccent.secondary),
                          const SizedBox(width: 10),
                          _KpiTile(label: 'VACANT', value: '$vacantCount',
                              accent: vacantCount > 0 ? KasaCardAccent.tertiary : KasaCardAccent.none),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Units heading ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text(
                  'UNITS',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    letterSpacing: 0.04, color: cs.kasaTextSub,
                  ),
                ),
              ),
            ),

            // ── Units list ────────────────────────────────────────────────
            if (units.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.meeting_room_outlined, size: 64, color: cs.kasaTextSub),
                      const SizedBox(height: 12),
                      Text('No units yet.',
                          style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w700, color: cs.kasaTextSub)),
                      const SizedBox(height: 4),
                      Text('Tap ADD UNIT to create one.',
                          style: GoogleFonts.inter(fontSize: 12, color: cs.kasaTextSub)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final u = units[i] as Map<String, dynamic>;
                      final uStatus = u['status'] as String? ?? 'vacant';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UnitCard(
                          unit: u,
                          status: uStatus,
                          canManage: canManage,
                          onOpen: () => context.push(
                            '/properties/$propertyId/units/${u['id']}',
                          ),
                          onEdit: () => showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => _EditUnitDialog(unit: u, onDone: onRefresh),
                          ),
                          onDelete: () async {
                            if (uStatus != 'vacant') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Only vacant units can be deleted.')),
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
                                      child: const Text('Cancel')),
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
                                await ref.read(dioProvider).delete('/api/v1/properties/units/${u['id']}/');
                                onRefresh();
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(apiError(e)),
                                    backgroundColor: Theme.of(context).colorScheme.error,
                                  ));
                                }
                              }
                            }
                          },
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

// ─── KPI tile ─────────────────────────────────────────────────────────────────

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value, required this.accent});
  final String label, value;
  final KasaCardAccent accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = switch (accent) {
      KasaCardAccent.secondary => cs.secondary,
      KasaCardAccent.tertiary  => cs.tertiary,
      KasaCardAccent.elevated  => cs.surfaceContainerHighest,
      _                        => cs.kasaCard,
    };
    final fg = switch (accent) {
      KasaCardAccent.secondary => cs.onSecondary,
      KasaCardAccent.tertiary  => cs.onTertiary,
      _                        => cs.onSurface,
    };
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(KasaRadius.sm),
          border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 28, fontWeight: FontWeight.w900, color: fg, height: 1)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    letterSpacing: 0.04, color: fg.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

// ─── Unit card ────────────────────────────────────────────────────────────────

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.status,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
  });
  final Map<String, dynamic> unit;
  final String status;
  final bool canManage;
  final VoidCallback onEdit, onDelete;

  /// Opens the unit's own screen. The row has always looked like a list item;
  /// until now only the overflow menu did anything, so tapping the row itself
  /// did nothing at all.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (accentColor, chipVariant, chipLabel) = switch (status) {
      'occupied'    => (cs.secondary,   KasaChipVariant.secondary, 'OCCUPIED'),
      'maintenance' => (cs.tertiary,    KasaChipVariant.tertiary,  'MAINTENANCE'),
      _             => (cs.kasaTextSub, KasaChipVariant.neutral,   'VACANT'),
    };

    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KasaRadius.md),
        boxShadow: [BoxShadow(color: cs.kasaShadow, offset: const Offset(4, 4), blurRadius: 0)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KasaRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: cs.kasaCard,
            border: Border(
              left:   BorderSide(color: accentColor,   width: 6),
              right:  BorderSide(color: cs.kasaStroke, width: 2),
              top:    BorderSide(color: cs.kasaStroke, width: 2),
              bottom: BorderSide(color: cs.kasaStroke, width: 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'UNIT ${unit['unit_number']}'.toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 15, fontWeight: FontWeight.w700,
                              letterSpacing: -0.15, color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          KasaChip(label: chipLabel, variant: chipVariant, small: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_unitTypeLabels[unit['unit_type']] ?? unit['unit_type']} · Floor ${unit['floor']}',
                        style: GoogleFonts.inter(fontSize: 11, color: cs.kasaTextSub),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatCurrency(toDouble(unit['rent_amount']))}/mo',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: cs.secondary, letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: cs.kasaTextSub, size: 20),
                  onSelected: (action) {
                    if (action == 'edit') onEdit();
                    if (action == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'edit',
                        child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), dense: true, contentPadding: EdgeInsets.zero)),
                    PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                            leading: Icon(Icons.delete_outline, color: Colors.red),
                            title: Text('Delete', style: TextStyle(color: Colors.red)),
                            dense: true,
                            contentPadding: EdgeInsets.zero)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
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

class _EditUnitDialog extends ConsumerStatefulWidget {
  const _EditUnitDialog({required this.unit, required this.onDone});
  final Map<String, dynamic> unit;
  final VoidCallback onDone;

  @override
  ConsumerState<_EditUnitDialog> createState() => _EditUnitDialogState();
}

class _EditUnitDialogState extends ConsumerState<_EditUnitDialog> {
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
