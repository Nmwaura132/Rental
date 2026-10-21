import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../dashboard/dashboard_screen.dart';
import 'maintenance_screen.dart';

/// The tenant's Repairs tab: what they have reported and where each one is,
/// with reporting a new one a tap away.
class TenantRepairsScreen extends ConsumerWidget {
  const TenantRepairsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final requests = ref.watch(maintenanceListProvider);
    final hasHome =
        ref.watch(dashboardProvider).valueOrNull?['tenancy_id'] != null;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Text('Repairs',
            style: KasaFont.sans(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
      ),
      bottomNavigationBar: hasHome
          ? KasaActionBar(children: [
              KasaButton(
                label: 'Report a repair',
                leading: Icon(Icons.add_rounded, size: 20, color: cs.onPrimary),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => const ReportRepairScreen()),
                ),
              ),
            ])
          : null,
      body: requests.when(
        loading: () => const SkeletonList(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: KasaNotice(icon: Icons.cloud_off_outlined, title: apiError(e)),
        ),
        data: (rows) {
          // Open ones first: those are what the tenant is waiting on.
          final open = rows
              .where(
                  (r) => r['status'] == 'open' || r['status'] == 'in_progress')
              .toList();
          final done = rows.where((r) => !open.contains(r)).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(maintenanceListProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (rows.isEmpty)
                  const KasaNotice(
                    icon: Icons.build_outlined,
                    title: 'Nothing reported',
                    body:
                        'If something in your home needs fixing, report it here. Your landlord '
                        'is told straight away and you can follow it to the end.',
                  ),
                if (open.isNotEmpty) ...[
                  const KasaSectionHeader('Waiting on'),
                  const SizedBox(height: 12),
                  KasaListGroup(
                      children: [for (final r in open) _RepairRow(request: r)]),
                  const SizedBox(height: 24),
                ],
                if (done.isNotEmpty) ...[
                  const KasaSectionHeader('Done'),
                  const SizedBox(height: 12),
                  KasaListGroup(
                      children: [for (final r in done) _RepairRow(request: r)]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RepairRow extends ConsumerWidget {
  const _RepairRow({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final reported = DateFormat('d MMM')
        .format(DateTime.parse('${r['created_at']}').toLocal());
    final fixed = r['resolved_at'] == null
        ? null
        : DateFormat('d MMM')
            .format(DateTime.parse('${r['resolved_at']}').toLocal());
    final (kind, label) = switch (r['status']) {
      'open' => (KasaStatusKind.due, 'Reported'),
      'in_progress' => (KasaStatusKind.due, 'Being fixed'),
      _ => (KasaStatusKind.paid, 'Fixed'),
    };
    final urgent = r['priority'] == 'urgent' || r['priority'] == 'high';
    return KasaListRow(
      leading: KasaLeadIcon(
          urgent ? Icons.priority_high_rounded : Icons.build_outlined,
          tone: urgent && fixed == null ? KasaStatusKind.overdue : null),
      title: '${r['title']}',
      subtitle: fixed == null
          ? 'Reported $reported'
          : 'Reported $reported · fixed $fixed',
      trailing: KasaStatusChip(kind: kind, label: label),
      onTap: () => openRepair(context, ref, request),
    );
  }
}

/// How bad it is, in the tenant's words rather than a priority scale.
const _urgency = [
  ('low', 'Can wait', 'Fix when convenient'),
  ('medium', 'Soon', 'This week'),
  ('urgent', 'Emergency', 'No water, a leak, no power, not safe'),
];

class ReportRepairScreen extends ConsumerStatefulWidget {
  const ReportRepairScreen({super.key});

  @override
  ConsumerState<ReportRepairScreen> createState() => _ReportRepairScreenState();
}

class _ReportRepairScreenState extends ConsumerState<ReportRepairScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  String _priority = 'medium';
  XFile? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, imageQuality: 85, maxWidth: 2000);
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  Future<void> _send(int tenancyId) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/api/v1/tenants/maintenance/',
          data: FormData.fromMap({
            'tenancy': '$tenancyId',
            'title': _title.text.trim(),
            'description': _details.text.trim(),
            'priority': _priority,
            if (_photo != null)
              'photo': await MultipartFile.fromFile(_photo!.path,
                  filename: _photo!.name),
          }));
      ref.invalidate(maintenanceListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reported. Your landlord has been told.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiError(e)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final home = ref.watch(dashboardProvider).valueOrNull ?? const {};
    final tenancyId = home['tenancy_id'] as int?;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
          backgroundColor: cs.kasaBg,
          surfaceTintColor: Colors.transparent,
          title: const Text('Report a repair')),
      bottomNavigationBar: KasaActionBar(children: [
        KasaButton(
          label: 'Send to landlord',
          isLoading: _busy,
          onTap: _busy || tenancyId == null ? null : () => _send(tenancyId),
        ),
      ]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (home['unit_number'] != null)
              Text('Unit ${home['unit_number']} · ${home['property_name']}',
                  style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'What needs fixing?',
                  hintText: 'e.g. Kitchen tap leaking'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Say what needs fixing' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _details,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText:
                    'Where it is, since when, anything the fundi should know',
              ),
            ),
            const SizedBox(height: 16),
            const KasaSectionHeader('How urgent?'),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _priority,
              onChanged: (v) => setState(() => _priority = v!),
              child: KasaListGroup(children: [
                for (final (value, title, hint) in _urgency)
                  RadioListTile<String>(
                    value: value,
                    title: Text(title,
                        style: KasaFont.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                    subtitle: Text(hint,
                        style:
                            KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
                  ),
              ]),
            ),
            const SizedBox(height: 24),
            const KasaSectionHeader('Photo (optional)'),
            const SizedBox(height: 12),
            if (_photo == null)
              Row(children: [
                Expanded(
                  child: KasaButton(
                    label: 'Take photo',
                    variant: KasaButtonVariant.secondary,
                    leading: Icon(Icons.photo_camera_outlined,
                        size: 18, color: cs.onSurface),
                    onTap: () => _pickPhoto(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KasaButton(
                    label: 'Gallery',
                    variant: KasaButtonVariant.secondary,
                    leading: Icon(Icons.photo_library_outlined,
                        size: 18, color: cs.onSurface),
                    onTap: () => _pickPhoto(ImageSource.gallery),
                  ),
                ),
              ])
            else
              KasaListGroup(children: [
                KasaListRow(
                  leading: const KasaLeadIcon(Icons.image_outlined),
                  title: 'Photo added',
                  subtitle: _photo!.name,
                  trailing: TextButton(
                      onPressed: () => setState(() => _photo = null),
                      child: const Text('Remove')),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
