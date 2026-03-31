import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/utils/api_error.dart';
import '../../shared/theme/app_theme.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

const _storage = FlutterSecureStorage();

final maintenanceListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/tenants/maintenance/');
  final data = resp.data;
  if (data is List) return List<Map<String, dynamic>>.from(data);
  if (data is Map && data['results'] is List) {
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }
  return [];
});



// ─── Constants ────────────────────────────────────────────────────────────────

const _statusLabels = {
  'open': 'Open',
  'in_progress': 'In Progress',
  'resolved': 'Resolved',
  'closed': 'Closed',
};

const _priorityLabels = {
  'low': 'Low',
  'medium': 'Medium',
  'high': 'High',
  'urgent': 'Urgent',
};

// ─── Screen ───────────────────────────────────────────────────────────────────

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  String? _selectedStatus; // null = show all
  String _role = '';

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await _storage.read(key: 'user_role') ?? '';
    if (mounted) setState(() => _role = role);
  }

  bool get _isTenant => _role == 'tenant';

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    if (_selectedStatus == null) return all;
    return all.where((r) => r['status'] == _selectedStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(maintenanceListProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.invalidate(maintenanceListProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _selectedStatus == null,
                  onTap: () => setState(() => _selectedStatus = null),
                ),
                ..._statusLabels.entries.map((e) => _FilterChip(
                      label: e.value,
                      selected: _selectedStatus == e.key,
                      onTap: () => setState(() => _selectedStatus = e.key),
                    )),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                message: 'Could not load requests',
                onRetry: () => ref.invalidate(maintenanceListProvider),
              ),
              data: (all) {
                final items = _filtered(all);
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.construction_outlined,
                            size: 64, color: cs.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          _selectedStatus == null
                              ? 'No maintenance requests'
                              : 'No ${_statusLabels[_selectedStatus]} requests',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.5),
                              fontSize: 16),
                        ),
                        if (_isTenant) ...[
                          const SizedBox(height: 8),
                          Text('Tap + to submit a new request',
                              style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.4),
                                  fontSize: 13)),
                        ],
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(maintenanceListProvider.future),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _RequestTile(
                      request: items[i],
                      isLandlord: !_isTenant,
                      onStatusChanged: () => ref.invalidate(maintenanceListProvider),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isTenant
          ? FloatingActionButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _showCreateDialog(context);
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showCreateDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateRequestSheet(
        onCreated: () {
          ref.invalidate(maintenanceListProvider);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ─── Filter Chip ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: cs.primaryContainer,
        checkmarkColor: cs.onPrimaryContainer,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? cs.onPrimaryContainer : cs.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ─── Request Tile ─────────────────────────────────────────────────────────────

class _RequestTile extends ConsumerWidget {
  const _RequestTile({
    required this.request,
    required this.isLandlord,
    required this.onStatusChanged,
  });

  final Map<String, dynamic> request;
  final bool isLandlord;
  final VoidCallback onStatusChanged;

  static final _fmt = DateFormat('dd MMM y');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final status = request['status'] as String? ?? 'open';
    final priority = request['priority'] as String? ?? 'medium';
    final title = request['title'] as String? ?? '—';
    final description = request['description'] as String? ?? '';
    final rawDate = request['created_at'];

    String dateStr = '';
    if (rawDate != null) {
      try {
        dateStr = _fmt.format(DateTime.parse(rawDate.toString()).toLocal());
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isLandlord
            ? () => _showStatusUpdateDialog(context, ref)
            : () => _showDetailSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  _PriorityBadge(priority: priority),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.7))),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _StatusBadge(status: status),
                  const Spacer(),
                  if (dateStr.isNotEmpty)
                    Text(dateStr,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5))),
                  if (isLandlord) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined,
                        size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetailSheet(request: request),
    );
  }

  void _showStatusUpdateDialog(BuildContext context, WidgetRef ref) {
    final currentStatus = request['status'] as String? ?? 'open';
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _StatusUpdateDialog(
        requestId: request['id'] as int,
        currentStatus: currentStatus,
        title: request['title'] as String? ?? '',
        ref: ref,
        onUpdated: onStatusChanged,
      ),
    );
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg, fg;
    switch (status) {
      case 'open':
        bg = cs.statusPendingBg;
        fg = cs.statusPending;
      case 'in_progress':
        bg = cs.statusVacantBg;
        fg = cs.statusVacant;
      case 'resolved':
        bg = cs.statusPaidBg;
        fg = cs.statusPaid;
      case 'closed':
        bg = cs.statusCancelledBg;
        fg = cs.statusCancelled;
      default:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurface;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _statusLabels[status] ?? status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─── Priority badge ───────────────────────────────────────────────────────────

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (priority) {
      case 'urgent':
        color = const Color(0xFFB71C1C);
      case 'high':
        color = const Color(0xFFE65100);
      case 'medium':
        color = const Color(0xFFF57F17);
      default:
        color = const Color(0xFF388E3C);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _priorityLabels[priority] ?? priority,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

// ─── Detail Sheet (tenant read-only) ─────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.request});
  final Map<String, dynamic> request;

  static final _fmt = DateFormat('dd MMM y · HH:mm');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = request['status'] as String? ?? '';
    final priority = request['priority'] as String? ?? '';
    final createdRaw = request['created_at'];
    final updatedRaw = request['updated_at'];

    String fmtDate(dynamic raw) {
      if (raw == null) return '—';
      try {
        return _fmt.format(DateTime.parse(raw.toString()).toLocal());
      } catch (_) {
        return raw.toString();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(request['title'] as String? ?? '—',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          Row(children: [
            _StatusBadge(status: status),
            const SizedBox(width: 8),
            _PriorityBadge(priority: priority),
          ]),
          const SizedBox(height: 14),
          if ((request['description'] as String? ?? '').isNotEmpty) ...[
            Text('Description',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 4),
            Text(request['description'] as String,
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 14),
          ],
          _InfoRow(label: 'Submitted', value: fmtDate(createdRaw)),
          _InfoRow(label: 'Last updated', value: fmtDate(updatedRaw)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Status Update Dialog (landlord/caretaker) ────────────────────────────────

class _StatusUpdateDialog extends ConsumerStatefulWidget {
  const _StatusUpdateDialog({
    required this.requestId,
    required this.currentStatus,
    required this.title,
    required this.ref,
    required this.onUpdated,
  });

  final int requestId;
  final String currentStatus;
  final String title;
  final WidgetRef ref;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_StatusUpdateDialog> createState() => _StatusUpdateDialogState();
}

class _StatusUpdateDialogState extends ConsumerState<_StatusUpdateDialog> {
  late String _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _status = widget.currentStatus;
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(
        '/api/v1/tenants/maintenance/${widget.requestId}/',
        data: {'status': _status},
      );
      widget.onUpdated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update Status'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 14),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: _statusLabels.entries.map(
              (e) => RadioListTile<String>(
                title: Text(e.value),
                value: e.key,
                // ignore: deprecated_member_use
                groupValue: _status,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _status = v!),
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
            ).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading || _status == widget.currentStatus ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Update'),
        ),
      ],
    );
  }
}

// ─── Create Request Sheet (tenant) ───────────────────────────────────────────

class _CreateRequestSheet extends ConsumerStatefulWidget {
  const _CreateRequestSheet({required this.onCreated});
  final VoidCallback onCreated;

  @override
  ConsumerState<_CreateRequestSheet> createState() => _CreateRequestSheetState();
}

class _CreateRequestSheetState extends ConsumerState<_CreateRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _priority = 'medium';
  bool _loading = false;
  int? _leaseId;
  String? _leaseLabel;
  bool _leasesLoading = true;
  String? _leasesError;

  @override
  void initState() {
    super.initState();
    _loadLease();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLease() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/api/v1/tenants/leases/', queryParameters: {'status': 'active'});
      final data = resp.data;
      List<dynamic> leases = [];
      if (data is List) {
        leases = data;
      } else if (data is Map && data['results'] is List) {
        leases = data['results'] as List;
      }
      if (leases.isNotEmpty) {
        final first = leases.first as Map<String, dynamic>;
        final unitNum = first['unit_number'] ?? first['unit'] ?? '';
        final propName = first['property_name'] ?? '';
        if (mounted) {
          setState(() {
            _leaseId = first['id'] as int?;
            _leaseLabel = propName.isNotEmpty ? '$propName — Unit $unitNum' : 'Unit $unitNum';
            _leasesLoading = false;
          });
        }
      } else {
        if (mounted) setState(() { _leasesLoading = false; _leasesError = 'No active lease found.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _leasesLoading = false; _leasesError = 'Could not load lease info.'; });
    }
  }

  Future<void> _submit() async {
    if (_leaseId == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/api/v1/tenants/maintenance/', data: {
        'lease': _leaseId,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'priority': _priority,
      });
      widget.onCreated();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('New Maintenance Request',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Lease info
            if (_leasesLoading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ))
            else if (_leasesError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Text(_leasesError!,
                      style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
                ]),
              )
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.home_outlined, color: cs.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_leaseLabel ?? '',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Leaking tap in kitchen',
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe the issue in detail',
                  alignLabelWithHint: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Text('Priority',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: _priorityLabels.entries.map((e) {
                  final selected = _priority == e.key;
                  return ChoiceChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (_) => setState(() => _priority = e.key),
                    selectedColor: cs.primaryContainer,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_loading || _leaseId == null) ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Submit Request'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Error view helper ────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
