import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/pagination.dart';
import '../../core/constants.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../shared/widgets/shimmer_loading.dart';

final leasesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  return fetchAllPages(dio, '/api/v1/tenants/leases/');
});

// Returns display status: 'active', 'ending', 'past'
String _leaseDisplayStatus(Map<String, dynamic> lease) {
  final status = lease['status'] as String? ?? '';
  if (status != 'active') return 'past';
  final endStr = lease['end_date'] as String?;
  if (endStr != null) {
    try {
      final end = DateTime.parse(endStr);
      final diff = end.difference(DateTime.now()).inDays;
      if (diff <= 60) return 'ending';
    } catch (_) {}
  }
  return 'active';
}

class TenantsScreen extends ConsumerStatefulWidget {
  const TenantsScreen({super.key});

  @override
  ConsumerState<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends ConsumerState<TenantsScreen> {
  String _filter = 'all';

  static const _filters = [
    ('all', 'ALL'),
    ('active', 'ACTIVE'),
    ('ending', 'ENDING'),
    ('past', 'PAST'),
  ];

  List<Map<String, dynamic>> _applyFilter(List<dynamic> all) {
    final list = all.cast<Map<String, dynamic>>();
    if (_filter == 'all') return list;
    return list.where((l) => _leaseDisplayStatus(l) == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final leases = ref.watch(leasesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'TENANTS',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.96,
                        color: cs.onSurface,
                        height: 1,
                      ),
                    ),
                  ),
                  KasaButton(
                    label: 'ADD',
                    variant: KasaButtonVariant.primary,
                    fullWidth: false,
                    leading: Icon(Icons.add, size: 16, color: cs.onPrimary),
                    onTap: () => _showOptions(context),
                  ),
                ],
              ),
            ),
          ),
          // Filter chips row
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              children: _filters.map((f) {
                final isSelected = _filter == f.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f.$1),
                    child: KasaChip(
                      label: f.$2,
                      variant: isSelected ? KasaChipVariant.secondary : KasaChipVariant.neutral,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: leases.when(
              loading: () => const SkeletonList(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 56, color: cs.kasaTextSub),
                    const SizedBox(height: 12),
                    Text(apiError(e),
                        style: GoogleFonts.inter(color: cs.kasaTextSub)),
                    const SizedBox(height: 16),
                    KasaButton(
                      label: 'RETRY',
                      variant: KasaButtonVariant.ghost,
                      leading: Icon(Icons.refresh, size: 16, color: cs.secondary),
                      onTap: () => ref.invalidate(leasesProvider),
                    ),
                  ],
                ),
              ),
              data: (raw) {
                final list = _applyFilter(raw);
                return list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: cs.kasaTextSub),
                            const SizedBox(height: 12),
                            Text(
                              raw.isEmpty ? 'No tenants yet.' : 'No results.',
                              style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.w700,
                                  color: cs.kasaTextSub)),
                            const SizedBox(height: 4),
                            Text(
                              raw.isEmpty ? 'Tap ADD to register a tenant.' : 'Try a different filter.',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: cs.kasaTextSub)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.refresh(leasesProvider.future),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final lease = list[i];
                            final name =
                                lease['tenant_name'] as String? ?? 'Unknown';
                            final apiStatus = lease['status'] as String? ?? 'unknown';
                            final displayStatus = _leaseDisplayStatus(lease);
                            final property = lease['property_name'] as String? ?? '';
                            final unit = lease['unit_number'] as String? ?? '';
                            final phone = lease['tenant_phone'] as String?;
                            final rent = lease['rent_amount'];
                            final endDate = lease['end_date'] as String?;

                            // Design: overdue→primary, ending→tertiary, active→secondary
                            final chipVariant = displayStatus == 'ending'
                                ? KasaChipVariant.tertiary
                                : displayStatus == 'past'
                                    ? KasaChipVariant.neutral
                                    : KasaChipVariant.secondary;
                            final chipLabel = displayStatus == 'ending'
                                ? 'ENDING'
                                : displayStatus == 'past'
                                    ? apiStatus.toUpperCase()
                                    : 'ACTIVE';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: KasaCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                onTap: null,
                                child: Row(
                                  children: [
                                    KasaAvatar(
                                      name: name,
                                      size: 48,
                                      accent: KasaCardAccent.secondary,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name.toUpperCase(),
                                                  style: GoogleFonts.spaceGrotesk(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: cs.onSurface,
                                                    letterSpacing: -0.14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              KasaChip(
                                                label: chipLabel,
                                                variant: chipVariant,
                                                small: true,
                                              ),
                                            ],
                                          ),
                                          if (property.isNotEmpty || unit.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'UNIT $unit · $property'.toUpperCase(),
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: cs.kasaTextSub,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (rent != null || endDate != null) ...[
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                if (endDate != null) ...[
                                                  Text(
                                                    'LEASE: $endDate',
                                                    style: GoogleFonts.spaceGrotesk(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      color: cs.kasaTextSub,
                                                    ),
                                                  ),
                                                  Text(
                                                    '  |  ',
                                                    style: TextStyle(color: cs.kasaTextSub, fontSize: 10),
                                                  ),
                                                ],
                                                if (rent != null)
                                                  Text(
                                                    'KES ${rent.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                                                    style: GoogleFonts.spaceGrotesk(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      color: cs.kasaTextSub,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                          if (phone != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              phone,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 11,
                                                color: cs.kasaTextSub,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (apiStatus == 'active')
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert,
                                            size: 20, color: cs.kasaTextSub),
                                        onSelected: (action) async {
                                          if (action == 'send_lease') {
                                            try {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'Generating lease PDF…')));
                                              final resp = await ref
                                                  .read(dioProvider)
                                                  .post(
                                                    '/api/v1/tenants/leases/${lease['id']}/send-lease/',
                                                  );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(
                                                      resp.data['message'] ??
                                                          'Done'),
                                                  backgroundColor: Colors.green,
                                                ));
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(apiError(e)),
                                                  backgroundColor: cs.error,
                                                ));
                                              }
                                            }
                                          } else if (action == 'terminate') {
                                            final confirmed =
                                                await showDialog<bool>(
                                              context: context,
                                              useRootNavigator: true,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                    'Terminate Lease'),
                                                content: Text(
                                                    'Terminate the lease for $name? '
                                                    'The unit will be marked vacant.'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, false),
                                                    child:
                                                        const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Theme.of(ctx)
                                                              .colorScheme
                                                              .error,
                                                      foregroundColor:
                                                          Colors.white,
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, true),
                                                    child: const Text(
                                                        'Terminate'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirmed == true &&
                                                context.mounted) {
                                              try {
                                                await ref
                                                    .read(dioProvider)
                                                    .patch(
                                                      '/api/v1/tenants/leases/${lease['id']}/',
                                                      data: {
                                                        'status': 'terminated'
                                                      },
                                                    );
                                                ref.invalidate(leasesProvider);
                                              } catch (e) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(SnackBar(
                                                    content: Text(apiError(e)),
                                                    backgroundColor: cs.error,
                                                  ));
                                                }
                                              }
                                            }
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'send_lease',
                                            child: ListTile(
                                              leading: Icon(
                                                  Icons.picture_as_pdf_outlined,
                                                  color: cs.secondary),
                                              title: const Text(
                                                  'Send Lease Agreement'),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'terminate',
                                            child: ListTile(
                                              leading: Icon(
                                                  Icons.cancel_outlined,
                                                  color: cs.error),
                                              title: Text('Terminate',
                                                  style: TextStyle(
                                                      color: cs.error)),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    // Await the options sheet — it returns which action the user chose.
    final cs = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: cs.kasaBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        final scs = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: scs.outlineVariant,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'ADD TENANT',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: scs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: KasaCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scs.secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scs.kasaStroke, width: 2),
                          ),
                          child: Icon(Icons.person_add,
                              size: 20, color: scs.onSecondaryContainer),
                        ),
                        title: Text('Add Tenant',
                            style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w700)),
                        subtitle: Text('Register a new tenant account',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: scs.kasaTextSub)),
                        trailing: Icon(Icons.chevron_right,
                            color: scs.kasaTextSub),
                        onTap: () => Navigator.pop(sheetCtx, 'addTenant'),
                      ),
                      Divider(height: 1, color: scs.kasaStroke, thickness: 2),
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scs.tertiaryContainer,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scs.kasaStroke, width: 2),
                          ),
                          child: Icon(Icons.assignment,
                              size: 20, color: scs.onTertiaryContainer),
                        ),
                        title: Text('New Lease',
                            style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w700)),
                        subtitle: Text('Assign a unit to an existing tenant',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: scs.kasaTextSub)),
                        trailing: Icon(Icons.chevron_right,
                            color: scs.kasaTextSub),
                        onTap: () => Navigator.pop(sheetCtx, 'newLease'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (action == null || !context.mounted) return;

    // Wait for the options sheet close animation (~300ms) to fully complete
    // before pushing the next modal. Without this delay, the new sheet is
    // pushed while the previous one is still animating out — causing the barrier
    // to appear (dark overlay) but the sheet content to fail to render.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!context.mounted) return;

    if (action == 'addTenant') {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            appBar: AppBar(
              title: const Text('Add Tenant'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: _AddTenantDialog(
              onDone: () => ref.invalidate(leasesProvider),
            ),
          ),
        ),
      );
    } else if (action == 'newLease') {
      showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => _AddLeaseDialog(
          onDone: () => ref.invalidate(leasesProvider),
        ),
      );
    }
  }
}

// ─── Add Tenant Dialog ────────────────────────────────────────────────────────

class _AddTenantDialog extends ConsumerStatefulWidget {
  const _AddTenantDialog({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_AddTenantDialog> createState() => _AddTenantDialogState();
}

class _AddTenantDialogState extends ConsumerState<_AddTenantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _kinNameCtrl = TextEditingController();
  final _kinPhoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _occupationType;
  XFile? _idFrontPhoto;
  XFile? _idBackPhoto;
  final _picker = ImagePicker();

  static const _occupationTypes = [
    'Employed',
    'Self-employed',
    'Student',
    'Business Owner',
    'Other',
  ];

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _idCtrl.dispose();
    _occupationCtrl.dispose();
    _kinNameCtrl.dispose();
    _kinPhoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.startsWith('0') && digits.length == 10) {
      return '+254${digits.substring(1)}';
    }
    if (digits.startsWith('254') && !digits.startsWith('+')) {
      return '+$digits';
    }
    if (!digits.startsWith('+')) return '+254$digits';
    return digits;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      // Build occupation string: type + detail if provided
      final occupationDetail = _occupationCtrl.text.trim();
      final occupation = _occupationType != null
          ? (occupationDetail.isNotEmpty
              ? '$_occupationType – $occupationDetail'
              : _occupationType)
          : occupationDetail.isNotEmpty
              ? occupationDetail
              : null;

      await dio.post('/api/v1/auth/register/', data: {
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        'phone_number': _normalizePhone(_phoneCtrl.text.trim()),
        'role': 'tenant',
        if (_idCtrl.text.trim().isNotEmpty) 'national_id': _idCtrl.text.trim(),
        if (occupation != null) 'occupation': occupation,
        if (_kinNameCtrl.text.trim().isNotEmpty)
          'next_of_kin_name': _kinNameCtrl.text.trim(),
        if (_kinPhoneCtrl.text.trim().isNotEmpty)
          'next_of_kin_phone': _normalizePhone(_kinPhoneCtrl.text.trim()),
        'password': _passCtrl.text,
        'password_confirm': _passCtrl.text,
      });

      // Upload ID photos if captured
      final phone = _normalizePhone(_phoneCtrl.text.trim());
      for (final entry in [
        ('front', _idFrontPhoto),
        ('back', _idBackPhoto),
      ]) {
        final side = entry.$1;
        final file = entry.$2;
        if (file != null) {
          try {
            await dio.post(
              '/api/v1/auth/upload-id/',
              data: FormData.fromMap({
                'side': side,
                'tenant_phone': phone,
                'photo': await MultipartFile.fromFile(
                  file.path,
                  filename: 'id_$side.jpg',
                ),
              }),
              options: Options(contentType: 'multipart/form-data'),
            );
          } catch (_) {
            // Non-fatal — tenant is created, photo can be uploaded later
          }
        }
      }

      widget.onDone();
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(
          content: Text('Tenant registered successfully.'),
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

  Future<void> _pickId(String side) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    setState(() {
      if (side == 'front') {
        _idFrontPhoto = file;
      } else {
        _idBackPhoto = file;
      }
    });
  }

  Widget _sectionLabel(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04,
          color: cs.kasaTextSub,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          // Scrollable form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Personal Info ──────────────────────────────
                    _sectionLabel('Personal Information'),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _firstCtrl,
                            decoration: const InputDecoration(
                                labelText: 'First Name *', isDense: true),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _lastCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Last Name *', isDense: true),
                              textCapitalization: TextCapitalization.words,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          hintText: '0712 345 678',
                          prefixIcon: Icon(Icons.phone),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v!.isEmpty) return 'Required';
                          final d = v.replaceAll(RegExp(r'[\s\-()]'), '');
                          final digits = d.startsWith('+') ? d.substring(1) : d;
                          if (!RegExp(r'^\d{7,15}$').hasMatch(digits)) {
                            return 'Enter a valid phone number';
                          }
                          return null;
                        },
                      ),

                      // ── Identity ───────────────────────────────────
                      _sectionLabel('Identity'),
                      TextFormField(
                        controller: _idCtrl,
                        decoration: const InputDecoration(
                          labelText: 'National ID Number',
                          hintText: 'e.g. 12345678',
                          prefixIcon: Icon(Icons.badge_outlined),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _IdPhotoTile(
                            label: 'ID Front',
                            file: _idFrontPhoto,
                            onTap: () => _pickId('front'),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _IdPhotoTile(
                            label: 'ID Back',
                            file: _idBackPhoto,
                            onTap: () => _pickId('back'),
                          )),
                        ],
                      ),

                      // ── Occupation ─────────────────────────────────
                      _sectionLabel('Occupation'),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                            labelText: 'Type', isDense: true),
                        initialValue: _occupationType,
                        hint: const Text('Select…'),
                        isExpanded: true,
                        items: _occupationTypes
                            .map((o) =>
                                DropdownMenuItem(value: o, child: Text(o)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _occupationType = v),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _occupationCtrl,
                        decoration: InputDecoration(
                          labelText: _occupationType == 'Student'
                              ? 'School / Institution'
                              : 'Employer / Business Name',
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),

                      // ── Next of Kin ────────────────────────────────
                      _sectionLabel('Next of Kin'),
                      TextFormField(
                        controller: _kinNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline),
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _kinPhoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '0712 345 678',
                          prefixIcon: Icon(Icons.phone_outlined),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.phone,
                      ),

                      // ── Account ────────────────────────────────────
                      _sectionLabel('Account Access'),
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Temporary Password *',
                          hintText: 'Min 8 characters',
                          prefixIcon: const Icon(Icons.lock_outline),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          if (v!.isEmpty) return 'Required';
                          if (v.length < 8) return 'Minimum 8 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Share this password with the tenant so they can log in.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),

            // Actions
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _loading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(120, 48),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Register Tenant'),
                  ),
                ],
              ),
            ),
          ],
    );
  }
}

// ─── Add Lease Dialog ─────────────────────────────────────────────────────────

class _AddLeaseDialog extends ConsumerStatefulWidget {
  const _AddLeaseDialog({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_AddLeaseDialog> createState() => _AddLeaseDialogState();
}

class _AddLeaseDialogState extends ConsumerState<_AddLeaseDialog> {
  // Data loaded on init
  List<Map<String, dynamic>> _tenants = [];
  List<Map<String, dynamic>> _properties = [];
  bool _initialLoading = true;
  String? _loadError;

  // Maps for fast lookup
  final Map<int, Map<String, dynamic>> _propertiesMap = {};
  final Map<int, Map<String, dynamic>> _unitsMap = {};

  // Selections
  int? _selectedTenantId;
  int? _selectedPropertyId;
  int? _selectedUnitId;
  List<Map<String, dynamic>> _vacantUnits = [];

  // Form fields
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  bool _depositPaid = false;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  final _fmt = DateFormat('dd MMM yyyy');
  final _apiDate = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadInitialData);
  }

  @override
  void dispose() {
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        fetchAllPages(dio, '/api/v1/auth/tenants/'),
        fetchAllPages(dio, '/api/v1/properties/'),
      ]);
      if (!mounted) return;

      final tenantList = results[0];
      final propList = results[1];
      setState(() {
        _tenants = tenantList.cast<Map<String, dynamic>>();
        _properties = propList.cast<Map<String, dynamic>>();
        for (final p in _properties) {
          _propertiesMap[p['id'] as int] = p;
        }
        _initialLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
        _loadError = e.toString();
        _initialLoading = false;
      });
      }
    }
  }

  void _onPropertyChanged(int? id) {
    final property = _propertiesMap[id];
    final vacantUnits = (property?['units'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((u) => u['status'] == 'vacant')
        .toList();
    _unitsMap.clear();
    for (final u in vacantUnits) {
      _unitsMap[u['id'] as int] = u;
    }
    setState(() {
      _selectedPropertyId = id;
      _selectedUnitId = null;
      _vacantUnits = vacantUnits;
      _rentCtrl.clear();
      _depositCtrl.clear();
    });
  }

  void _onUnitChanged(int? id) {
    final unit = _unitsMap[id];
    setState(() {
      _selectedUnitId = id;
      if (unit != null) {
        _rentCtrl.text = unit['rent_amount'].toString();
        _depositCtrl.text = unit['deposit_amount'].toString();
      }
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_endDate ?? _startDate);
    final first = isStart ? DateTime(2020) : _startDate;
    final last = DateTime(2035);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedTenantId == null || _selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tenant and unit.')),
      );
      return;
    }
    final rent = double.tryParse(_rentCtrl.text.replaceAll(',', ''));
    final deposit = double.tryParse(_depositCtrl.text.replaceAll(',', ''));
    if (rent == null || deposit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid rent and deposit amounts.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/api/v1/tenants/leases/', data: {
        'tenant': _selectedTenantId,
        'unit': _selectedUnitId,
        'start_date': _apiDate.format(_startDate),
        if (_endDate != null) 'end_date': _apiDate.format(_endDate!),
        'rent_amount': rent,
        'deposit_amount': deposit,
        'deposit_paid': _depositPaid,
        'notes': _notesCtrl.text.trim(),
      });
      widget.onDone();
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(
          content: Text('Lease created successfully.'),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Lease'),
      content: _initialLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : _loadError != null
              ? Text('Error loading data: $_loadError')
              : SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tenant picker
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tenant *'),
                        initialValue: _selectedTenantId,
                        hint: _tenants.isEmpty
                            ? const Text('No tenants — add one first', overflow: TextOverflow.ellipsis)
                            : const Text('Select tenant', overflow: TextOverflow.ellipsis),
                        items: _tenants
                            .map((t) => DropdownMenuItem<int>(
                                  value: t['id'] as int,
                                  child: Text(
                                      '${t['first_name']} ${t['last_name']}',
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedTenantId = v),
                      ),
                      const SizedBox(height: 12),

                      // Property picker
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Property *'),
                        initialValue: _selectedPropertyId,
                        hint: _properties.isEmpty
                            ? const Text('No properties — add one first', overflow: TextOverflow.ellipsis)
                            : const Text('Select property', overflow: TextOverflow.ellipsis),
                        items: _properties
                            .map((p) => DropdownMenuItem<int>(
                                  value: p['id'] as int,
                                  child: Text(p['name'] as String,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: _onPropertyChanged,
                      ),
                      const SizedBox(height: 12),

                      // Unit picker (only shown after property selected)
                      if (_selectedPropertyId != null)
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Vacant Unit *'),
                          initialValue: _selectedUnitId,
                          hint: _vacantUnits.isEmpty
                              ? const Text('No vacant units', overflow: TextOverflow.ellipsis)
                              : const Text('Select unit', overflow: TextOverflow.ellipsis),
                          items: _vacantUnits
                              .map((u) => DropdownMenuItem<int>(
                                    value: u['id'] as int,
                                    child: Text(
                                        'Unit ${u['unit_number']} — ${_unitTypeLabel(u['unit_type'])}',
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: _vacantUnits.isEmpty ? null : _onUnitChanged,
                        ),
                      const SizedBox(height: 12),

                      // Rent & Deposit
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _rentCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Rent (${AppConstants.currency})', prefixText: '${AppConstants.currency} '),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _depositCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Deposit (${AppConstants.currency})', prefixText: '${AppConstants.currency} '),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Start date
                      InkWell(
                        onTap: () => _pickDate(isStart: true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Start Date *',
                              suffixIcon: Icon(Icons.calendar_today)),
                          child: Text(_fmt.format(_startDate)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // End date (optional)
                      InkWell(
                        onTap: () => _pickDate(isStart: false),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'End Date (optional)',
                              suffixIcon: Icon(Icons.calendar_today)),
                          child: Text(
                              _endDate != null ? _fmt.format(_endDate!) : 'Open-ended'),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Deposit paid
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Deposit already paid'),
                        value: _depositPaid,
                        onChanged: (v) => setState(() => _depositPaid = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_submitting || _initialLoading) ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create Lease'),
        ),
      ],
    );
  }

  String _unitTypeLabel(dynamic type) {
    const labels = {
      'bedsitter': 'Bedsitter',
      '1bed': '1 Bed',
      '2bed': '2 Bed',
      '3bed': '3 Bed',
      'studio': 'Studio',
      'commercial': 'Commercial',
    };
    return labels[type] ?? type.toString();
  }
}

// ─── ID Photo Tile ────────────────────────────────────────────────────────────

class _IdPhotoTile extends StatelessWidget {
  const _IdPhotoTile({
    required this.label,
    required this.file,
    required this.onTap,
  });
  final String label;
  final XFile? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: hasPhoto
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasPhoto
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.4),
            width: hasPhoto ? 1.5 : 1,
          ),
        ),
        child: hasPhoto
            ? ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.network(
                  file!.path,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(theme, label, true),
                ),
              )
            : _placeholder(theme, label, false),
      ),
    );
  }

  Widget _placeholder(ThemeData theme, String label, bool captured) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          captured ? Icons.check_circle_outline : Icons.add_a_photo_outlined,
          color: captured ? theme.colorScheme.primary : theme.colorScheme.outline,
          size: 28,
        ),
        const SizedBox(height: 4),
        Text(
          captured ? 'Captured' : label,
          style: TextStyle(
            fontSize: 11,
            color: captured ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
