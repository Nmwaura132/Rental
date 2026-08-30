import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart' show FormData, MultipartFile;

import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/constants.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/utils/api_error.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/widgets/kasa_primitives.dart';

// ─── Providers ────────────────────────────────────────────────────────────────


final maintenanceListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final data = await fetchAllPages(dio, '/api/v1/tenants/maintenance/');
  return List<Map<String, dynamic>>.from(data);
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

enum _SortBy { newest, oldest, priority }

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  String? _selectedStatus;   // null = show all statuses
  String? _selectedPriority; // null = show all priorities
  _SortBy _sortBy = _SortBy.newest;

  bool get _isTenant =>
      ref.watch(userRoleProvider).valueOrNull == 'tenant';

  // WHY: ordered priority severity for the priority-sort path. Higher index = more urgent.
  static const _priorityRank = {'low': 0, 'medium': 1, 'high': 2, 'urgent': 3};

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    final filtered = all.where((r) {
      if (_selectedStatus != null && r['status'] != _selectedStatus) return false;
      if (_selectedPriority != null && r['priority'] != _selectedPriority) return false;
      return true;
    }).toList();

    int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (_sortBy) {
        case _SortBy.newest:
          return (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString());
        case _SortBy.oldest:
          return (a['created_at'] ?? '').toString().compareTo((b['created_at'] ?? '').toString());
        case _SortBy.priority:
          final pa = _priorityRank[a['priority']] ?? -1;
          final pb = _priorityRank[b['priority']] ?? -1;
          if (pa != pb) return pb.compareTo(pa);
          // Tie-break on newest first
          return (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString());
      }
    }

    filtered.sort(compare);
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(maintenanceListProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Text(
                    'MAINTENANCE',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.96,
                      color: cs.onSurface,
                      height: 1,
                    ),
                  ),
                  const Spacer(),
                  // Sort menu — newest / oldest / priority
                  PopupMenuButton<_SortBy>(
                    tooltip: 'Sort',
                    icon: Icon(Icons.sort, size: 22, color: cs.onSurface),
                    onSelected: (v) => setState(() => _sortBy = v),
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: _SortBy.newest,
                        checked: _sortBy == _SortBy.newest,
                        child: const Text('Newest first'),
                      ),
                      CheckedPopupMenuItem(
                        value: _SortBy.oldest,
                        checked: _sortBy == _SortBy.oldest,
                        child: const Text('Oldest first'),
                      ),
                      CheckedPopupMenuItem(
                        value: _SortBy.priority,
                        checked: _sortBy == _SortBy.priority,
                        child: const Text('Priority (high → low)'),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh, size: 22, color: cs.onSurface),
                    tooltip: 'Refresh',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.invalidate(maintenanceListProvider);
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Status filter chips ──────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _selectedStatus = null),
                  child: KasaChip(
                    label: 'ALL',
                    variant: _selectedStatus == null
                        ? KasaChipVariant.secondary
                        : KasaChipVariant.neutral,
                  ),
                ),
                ..._statusLabels.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedStatus = e.key),
                    child: KasaChip(
                      label: e.value.toUpperCase(),
                      variant: _selectedStatus == e.key
                          ? KasaChipVariant.secondary
                          : KasaChipVariant.neutral,
                    ),
                  ),
                )),
              ],
            ),
          ),

          // ── Priority filter chips ───────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _selectedPriority = null),
                  child: KasaChip(
                    label: 'ANY',
                    // WHY: tertiary variant distinguishes the priority row from
                    // the status row visually without adding a label.
                    variant: _selectedPriority == null
                        ? KasaChipVariant.tertiary
                        : KasaChipVariant.neutral,
                  ),
                ),
                ..._priorityLabels.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPriority = e.key),
                    child: KasaChip(
                      label: e.value.toUpperCase(),
                      variant: _selectedPriority == e.key
                          ? KasaChipVariant.tertiary
                          : KasaChipVariant.neutral,
                    ),
                  ),
                )),
              ],
            ),
          ),
          Expanded(
            child: KasaContentSwitcher(
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
                        onChanged: () => ref.invalidate(maintenanceListProvider),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isTenant
          ? Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: FloatingActionButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showCreateDialog(context);
                },
                child: const Icon(Icons.add),
              ),
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

// ─── Request Tile ─────────────────────────────────────────────────────────────

class _RequestTile extends ConsumerWidget {
  const _RequestTile({
    required this.request,
    required this.isLandlord,
    required this.onChanged,
  });

  final Map<String, dynamic> request;
  final bool isLandlord;
  // WHY: fires after edit/delete/status-change in the detail sheet. Drives
  // the parent's ref.invalidate(maintenanceListProvider) so the list refreshes.
  final VoidCallback onChanged;

  static final _fmt = DateFormat('dd MMM y');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final status = request['status'] as String? ?? 'open';
    final priority = request['priority'] as String? ?? 'medium';
    final title = request['title'] as String? ?? '—';
    final description = request['description'] as String? ?? '';
    final rawDate = request['created_at'];
    final tenantName = request['tenant_name'] as String? ?? '';
    final unitNumber = request['unit_number'] as String? ?? '';

    String dateStr = '';
    if (rawDate != null) {
      try {
        dateStr = _fmt.format(DateTime.parse(rawDate.toString()).toLocal());
      } catch (_) {}
    }

    // Accent color drives the thick left border (design: open→secondary, progress→tertiary, resolved→primary)
    final accentColor = switch (status) {
      'open'        => cs.secondary,
      'in_progress' => cs.tertiary,
      'resolved'    => cs.primary,
      _             => cs.outline,
    };

    // Priority icon in the left column
    final priorityIcon = switch (priority) {
      'urgent' => Icons.warning_amber_rounded,
      'high'   => Icons.arrow_upward_rounded,
      'low'    => Icons.arrow_downward_rounded,
      _        => Icons.remove_rounded,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        // WHY: both roles now open the full detail sheet. Landlord-specific
        // actions (status change, edit, delete) live INSIDE the sheet so the
        // landlord sees full context (description, photo, replies) before acting.
        onTap: () => _showDetailSheet(context),
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
                  left:   BorderSide(color: accentColor,    width: 8),
                  right:  BorderSide(color: cs.kasaStroke,  width: 2),
                  top:    BorderSide(color: cs.kasaStroke,  width: 2),
                  bottom: BorderSide(color: cs.kasaStroke,  width: 2),
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icon column — 52px wide, elev background
                    Container(
                      width: 52,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        border: Border(right: BorderSide(color: cs.kasaStroke, width: 2)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(priorityIcon, size: 22, color: cs.onSurface),
                    ),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title.toUpperCase(),
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 14, fontWeight: FontWeight.w700,
                                      letterSpacing: -0.14, color: cs.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  // WHY: landlord needs to know whose unit a request is for
                                  // without tapping in. Tenants only see their own requests
                                  // so this row would be redundant for them.
                                  if (isLandlord && (tenantName.isNotEmpty || unitNumber.isNotEmpty)) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (unitNumber.isNotEmpty) 'UNIT $unitNumber',
                                        if (tenantName.isNotEmpty) tenantName.toUpperCase(),
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 10, fontWeight: FontWeight.w700,
                                        letterSpacing: 0.04, color: cs.kasaTextSub,
                                      ),
                                    ),
                                  ],
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11, fontWeight: FontWeight.w500,
                                        color: cs.kasaTextSub,
                                      ),
                                    ),
                                  ],
                                  if (dateStr.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'SUBMITTED $dateStr',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 10, fontWeight: FontWeight.w700,
                                        letterSpacing: 0.04, color: cs.kasaTextSub,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _StatusBadge(status: status),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.kasaCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetailSheet(
        request: request,
        isLandlord: isLandlord,
        onChanged: onChanged,
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
    final variant = switch (status) {
      'open'        => KasaChipVariant.secondary,
      'in_progress' => KasaChipVariant.tertiary,
      'resolved'    => KasaChipVariant.primary,
      _             => KasaChipVariant.neutral,
    };
    final label = switch (status) {
      'open'        => 'OPEN',
      'in_progress' => 'IN PROGRESS',
      'resolved'    => 'RESOLVED',
      'closed'      => 'CLOSED',
      _             => status.replaceAll('_', ' ').toUpperCase(),
    };
    return KasaChip(label: label, variant: variant, small: true);
  }
}

// ─── Priority badge ───────────────────────────────────────────────────────────

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (priority) {
      'urgent' => cs.error,
      'high'   => cs.tertiary,
      'medium' => cs.secondary,
      _        => cs.kasaTextSub,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KasaRadius.pill),
        border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
      ),
      child: Text(
        (_priorityLabels[priority] ?? priority).toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10, fontWeight: FontWeight.w700,
          letterSpacing: 0.04, color: color,
        ),
      ),
    );
  }
}

// ─── Detail Sheet (shared — landlord sees edit/delete/status; tenant sees view+reply) ─

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet({
    required this.request,
    required this.isLandlord,
    required this.onChanged,
  });

  final Map<String, dynamic> request;
  final bool isLandlord;
  final VoidCallback onChanged;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  static final _fmt = DateFormat('dd MMM y · HH:mm');

  List<Map<String, dynamic>> _notes = [];
  bool _notesLoading = true;
  bool _sending = false;
  final _replyCtrl = TextEditingController();

  // Local mutable snapshot of the request so edits + status changes reflect
  // immediately without waiting for the parent list to refresh.
  late Map<String, dynamic> _req;
  bool _saving = false;          // PATCH-in-flight flag for edit/status mutations
  bool _editMode = false;        // landlord-only inline edit
  TextEditingController? _editTitleCtrl;
  TextEditingController? _editDescCtrl;
  String? _editPriority;

  @override
  void initState() {
    super.initState();
    _req = Map<String, dynamic>.from(widget.request);
    _loadNotes();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _editTitleCtrl?.dispose();
    _editDescCtrl?.dispose();
    super.dispose();
  }

  // ── Landlord-only mutations ────────────────────────────────────────────────

  Future<void> _patch(Map<String, dynamic> body) async {
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.patch(
        '/api/v1/tenants/maintenance/${_req['id']}/',
        data: body,
      );
      if (mounted) {
        setState(() {
          _req = Map<String, dynamic>.from(resp.data as Map);
          _saving = false;
        });
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<void> _changeStatus(String newStatus) async {
    if (newStatus == _req['status']) return;
    await _patch({'status': newStatus});
  }

  void _enterEditMode() {
    setState(() {
      _editMode = true;
      _editTitleCtrl = TextEditingController(text: _req['title'] as String? ?? '');
      _editDescCtrl = TextEditingController(text: _req['description'] as String? ?? '');
      _editPriority = _req['priority'] as String? ?? 'medium';
    });
  }

  void _cancelEdit() {
    setState(() {
      _editMode = false;
      _editTitleCtrl?.dispose();
      _editDescCtrl?.dispose();
      _editTitleCtrl = null;
      _editDescCtrl = null;
      _editPriority = null;
    });
  }

  Future<void> _saveEdit() async {
    final title = _editTitleCtrl?.text.trim() ?? '';
    final desc = _editDescCtrl?.text.trim() ?? '';
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title cannot be empty.')),
      );
      return;
    }
    await _patch({
      'title': title,
      'description': desc,
      'priority': _editPriority,
    });
    if (mounted) _cancelEdit();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete request?'),
        content: Text(
          'This will permanently delete "${_req['title'] ?? 'this request'}" and all its replies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/api/v1/tenants/maintenance/${_req['id']}/');
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  Future<void> _loadNotes() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/api/v1/tenants/maintenance/${_req['id']}/notes/');
      final data = resp.data;
      if (mounted) {
        setState(() {
          _notes = List<Map<String, dynamic>>.from(data is List ? data : []);
          _notesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _notesLoading = false);
    }
  }

  Future<void> _sendReply() async {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post(
        '/api/v1/tenants/maintenance/${_req['id']}/notes/',
        data: {'body': body},
      );
      _replyCtrl.clear();
      if (mounted) {
        setState(() {
          _notes.add(Map<String, dynamic>.from(resp.data as Map));
          _sending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiError(e)),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try { return _fmt.format(DateTime.parse(raw.toString()).toLocal()); }
    catch (_) { return raw.toString(); }
  }



  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _req['status'] as String? ?? '';
    final priority = _req['priority'] as String? ?? '';
    final rawPhoto = _req['photo'];
    final photoUrl = rawPhoto != null && (rawPhoto as String).isNotEmpty
        ? AppConstants.resolveMediaUrl(rawPhoto)
        : null;
    final tenantName = _req['tenant_name'] as String? ?? '';
    final unitNumber = _req['unit_number'] as String? ?? '';
    final propertyName = _req['property_name'] as String? ?? '';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Scrollable body
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              children: [
                // Title row — title + landlord overflow menu (edit/delete)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _editMode
                          ? TextField(
                              controller: _editTitleCtrl,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 20, fontWeight: FontWeight.w700,
                                letterSpacing: -0.4, color: cs.onSurface,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'Title',
                              ),
                            )
                          : Text(
                              (_req['title'] as String? ?? '—').toUpperCase(),
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 20, fontWeight: FontWeight.w700,
                                letterSpacing: -0.4, color: cs.onSurface,
                              ),
                            ),
                    ),
                    if (widget.isLandlord && !_editMode)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: Icon(Icons.more_vert, color: cs.onSurface),
                        onSelected: (v) {
                          switch (v) {
                            case 'edit':
                              _enterEditMode();
                              break;
                            case 'delete':
                              _confirmDelete();
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Tenant / unit context — landlord only (tenant already knows their own)
                if (widget.isLandlord && (tenantName.isNotEmpty || unitNumber.isNotEmpty)) ...[
                  Text(
                    [
                      if (propertyName.isNotEmpty) propertyName,
                      if (unitNumber.isNotEmpty) 'Unit $unitNumber',
                      if (tenantName.isNotEmpty) tenantName,
                    ].join(' · '),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      letterSpacing: 0.02, color: cs.kasaTextSub,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Status + priority badges (read-only display; status is editable below)
                Row(children: [
                  _StatusBadge(status: status),
                  const SizedBox(width: 8),
                  if (_editMode)
                    // In edit mode, priority becomes a dropdown
                    DropdownButton<String>(
                      value: _editPriority,
                      underline: const SizedBox.shrink(),
                      items: _priorityLabels.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _editPriority = v);
                      },
                    )
                  else
                    _PriorityBadge(priority: priority),
                ]),
                const SizedBox(height: 14),

                // Landlord-only status switcher
                if (widget.isLandlord && !_editMode) ...[
                  const _SectionLabel('CHANGE STATUS'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _statusLabels.entries.map((e) {
                      final selected = e.key == status;
                      return GestureDetector(
                        onTap: _saving || selected ? null : () => _changeStatus(e.key),
                        child: KasaChip(
                          label: e.value.toUpperCase(),
                          variant: selected
                              ? KasaChipVariant.secondary
                              : KasaChipVariant.neutral,
                        ),
                      );
                    }).toList(),
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(minHeight: 2, color: cs.secondary),
                  ],
                  const SizedBox(height: 14),
                ],

                // Description
                if (_editMode) ...[
                  const _SectionLabel('DESCRIPTION'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _editDescCtrl,
                    maxLines: 4,
                    style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Describe the issue',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : _cancelEdit,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saving ? null : _saveEdit,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ] else if ((_req['description'] as String? ?? '').isNotEmpty) ...[
                  const _SectionLabel('DESCRIPTION'),
                  const SizedBox(height: 4),
                  Text(_req['description'] as String,
                      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface)),
                  const SizedBox(height: 14),
                ],

                // Photo
                if (photoUrl != null) ...[
                  const _SectionLabel('PHOTO'),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(KasaRadius.md),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                        borderRadius: BorderRadius.circular(KasaRadius.md),
                        boxShadow: [BoxShadow(color: cs.kasaShadow, offset: const Offset(4, 4), blurRadius: 0)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(KasaRadius.md - KasaBorders.card),
                        child: Image.network(
                          photoUrl,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                ),
                          errorBuilder: (_, __, ___) => Container(
                            height: 80,
                            color: cs.surfaceContainerHighest,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined,
                                  color: cs.kasaTextSub),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Meta
                _InfoRow(label: 'Submitted', value: _fmtDate(_req['created_at'])),
                _InfoRow(label: 'Last updated', value: _fmtDate(_req['updated_at'])),
                // WHY: only show resolved_at when the API actually returned one
                // (not "—" placeholder). Closed/in_progress requests with no
                // resolved_at would otherwise show a misleading dash.
                if (_req['resolved_at'] != null)
                  _InfoRow(label: 'Resolved', value: _fmtDate(_req['resolved_at'])),
                const SizedBox(height: 20),

                // Notes / replies
                _SectionLabel('REPLIES (${_notes.length})'),
                const SizedBox(height: 8),
                if (_notesLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  ))
                else if (_notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No replies yet. Be the first to add one.',
                        style: GoogleFonts.inter(fontSize: 13, color: cs.kasaTextSub)),
                  )
                else
                  ..._notes.map((n) => _NoteCard(note: n)),

                const SizedBox(height: 12),
              ],
            ),
          ),

          // Reply input bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(
              color: cs.kasaCard,
              border: Border(top: BorderSide(color: cs.kasaStroke, width: KasaBorders.card)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.kasaBg,
                      borderRadius: BorderRadius.circular(KasaRadius.sm),
                      border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                    ),
                    child: TextField(
                      controller: _replyCtrl,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Add a reply…',
                        hintStyle: GoogleFonts.inter(fontSize: 14, color: cs.kasaTextSub),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sending ? null : _sendReply,
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: cs.secondary,
                      borderRadius: BorderRadius.circular(KasaRadius.sm),
                      border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                      boxShadow: [BoxShadow(color: cs.kasaShadow, offset: const Offset(3, 3), blurRadius: 0)],
                    ),
                    child: _sending
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSecondary),
                          )
                        : Icon(Icons.send_rounded, size: 20, color: cs.onSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 11, fontWeight: FontWeight.w700,
        letterSpacing: 0.04, color: cs.kasaTextSub,
      ),
    );
  }
}

// ─── Note / reply card ────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final Map<String, dynamic> note;

  static final _fmt = DateFormat('dd MMM · HH:mm');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTenant = note['is_tenant'] as bool? ?? false;
    final author = note['author_name'] as String? ?? 'Unknown';
    final body = note['body'] as String? ?? '';
    final raw = note['created_at'];
    String timeStr = '';
    if (raw != null) {
      try { timeStr = _fmt.format(DateTime.parse(raw.toString()).toLocal()); }
      catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: isTenant ? cs.secondary.withValues(alpha: 0.08) : cs.kasaCard,
          borderRadius: BorderRadius.circular(KasaRadius.sm),
          border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: isTenant ? cs.secondary : cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    author.isNotEmpty ? author[0].toUpperCase() : '?',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: isTenant ? cs.onSecondary : cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    author.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (timeStr.isNotEmpty)
                  Text(timeStr,
                      style: GoogleFonts.inter(fontSize: 10, color: cs.kasaTextSub)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface)),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 0.04, color: cs.kasaTextSub,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface,
            ),
          ),
        ],
      ),
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
  XFile? _photo;
  final _picker = ImagePicker();
  int? _tenancyId;
  String? _tenancyLabel;
  bool _tenanciesLoading = true;
  String? _tenanciesError;

  @override
  void initState() {
    super.initState();
    _loadTenancy();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTenancy() async {
    try {
      final dio = ref.read(dioProvider);
      final tenancies = await fetchAllPages(
        dio,
        '/api/v1/tenants/tenancies/',
        queryParameters: {'status': 'active'},
      );
      if (tenancies.isNotEmpty) {
        final first = tenancies.first as Map<String, dynamic>;
        final unitNum = first['unit_number'] ?? first['unit'] ?? '';
        final propName = first['property_name'] ?? '';
        if (mounted) {
          setState(() {
            _tenancyId = first['id'] as int?;
            _tenancyLabel = propName.isNotEmpty ? '$propName — Unit $unitNum' : 'Unit $unitNum';
            _tenanciesLoading = false;
          });
        }
      } else {
        if (mounted) setState(() { _tenanciesLoading = false; _tenanciesError = 'No active tenancy found.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _tenanciesLoading = false; _tenanciesError = 'Could not load tenancy info.'; });
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  Future<void> _submit() async {
    if (_tenancyId == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'tenancy': _tenancyId.toString(),
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'priority': _priority,
        if (_photo != null)
          'photo': await MultipartFile.fromFile(_photo!.path,
              filename: _photo!.name),
      });
      await dio.post('/api/v1/tenants/maintenance/', data: formData);
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

            // Tenancy info
            if (_tenanciesLoading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ))
            else if (_tenanciesError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Text(_tenanciesError!,
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
                    child: Text(_tenancyLabel ?? '',
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
              const SizedBox(height: 14),
              Text('Photo (optional)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: cs.outlineVariant, style: BorderStyle.solid),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _photo != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(_photo!.path), fit: BoxFit.cover),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => setState(() => _photo = null),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.close,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 32, color: cs.onSurface.withValues(alpha: 0.4)),
                            const SizedBox(height: 6),
                            Text('Tap to attach photo',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.4))),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_loading || _tenancyId == null) ? null : _submit,
                  child: _loading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.onPrimary,
                              strokeWidth: 2))
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
