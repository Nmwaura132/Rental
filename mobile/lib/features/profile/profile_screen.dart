import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/api_client.dart';
import '../../core/utils/api_error.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/constants.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/widgets/kasa_primitives.dart';

const _storage = FlutterSecureStorage();

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _name = '';
  String _phone = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final name = await _storage.read(key: 'user_name') ?? '';
    final phone = await _storage.read(key: 'user_phone') ?? '';
    final role = await _storage.read(key: 'user_role') ?? '';
    if (mounted) {
      setState(() {
        _name = name;
        _phone = phone;
        _role = role;
      });
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
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
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _storage.deleteAll();
      if (mounted) context.go('/login');
    }
  }

  void _showChangePasswordDialog() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool loading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Change Password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Current Password'),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New Password'),
                  validator: (v) =>
                      v!.length < 8 ? 'Min 8 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm New Password'),
                  validator: (v) =>
                      v != newCtrl.text ? 'Passwords do not match' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setS(() => loading = true);
                      try {
                        final dio = ref.read(dioProvider);
                        await dio.post('/api/v1/auth/change-password/', data: {
                          'old_password': oldCtrl.text,
                          'new_password': newCtrl.text,
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password changed successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setS(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(apiError(e)),
                            backgroundColor:
                                Theme.of(ctx).colorScheme.error,
                          ));
                        }
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;

    final isLandlord = _role.toLowerCase() == 'landlord';
    final roleChipVariant =
        isLandlord ? KasaChipVariant.primary : KasaChipVariant.secondary;
    final avatarAccent =
        isLandlord ? KasaCardAccent.primary : KasaCardAccent.secondary;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      body: SafeArea(
        child: ListView(
          children: [
            // ── Page heading ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Text(
                'PROFILE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.96,
                  color: cs.onSurface,
                  height: 1,
                ),
              ),
            ),

            // ── User info card ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: KasaCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Role chip — top-right aligned
                    if (_role.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: KasaChip(
                          label: _role,
                          variant: roleChipVariant,
                          small: true,
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Avatar + name + phone — centred
                    Column(
                      children: [
                        KasaAvatar(
                          name: _name.isNotEmpty ? _name : '?',
                          size: 88,
                          accent: avatarAccent,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _name,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.02 * 24,
                            color: cs.onSurface,
                            height: 1.1,
                          ),
                        ),
                        if (_phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _phone,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.kasaTextSub,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── ACCOUNT section ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                'ACCOUNT',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.04,
                  color: cs.kasaTextSub,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: KasaCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'NAME',
                      value: _name,
                      isFirst: true,
                    ),
                    _DetailRow(
                      label: 'PHONE',
                      value: _phone,
                      valueStyle: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    _DetailRow(
                      label: 'ROLE',
                      value: _role.isNotEmpty ? _role.toUpperCase() : '—',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── PREFERENCES section ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                'PREFERENCES',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.04,
                  color: cs.kasaTextSub,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: KasaCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Theme row
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      child: Row(
                        children: [
                          Text(
                            'THEME',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.04,
                              color: cs.kasaTextSub,
                            ),
                          ),
                          const Spacer(),
                          SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.brightness_auto, size: 16),
                                  label: Text('Auto')),
                              ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.light_mode, size: 16),
                                  label: Text('Light')),
                              ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode, size: 16),
                                  label: Text('Dark')),
                            ],
                            selected: {themeMode},
                            onSelectionChanged: (sel) => ref
                                .read(themeModeProvider.notifier)
                                .setMode(sel.first),
                            style: const ButtonStyle(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Password row
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: cs.kasaStroke, width: 2),
                        ),
                      ),
                      child: GestureDetector(
                        onTap: _showChangePasswordDialog,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          child: Row(
                            children: [
                              Text(
                                'PASSWORD',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.04,
                                  color: cs.kasaTextSub,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: cs.kasaTextSub,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Server URL row
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: cs.kasaStroke, width: 2),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      child: Row(
                        children: [
                          Text(
                            'SERVER',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.04,
                              color: cs.kasaTextSub,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppConstants.apiBaseUrl,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: cs.kasaTextSub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Action buttons ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Switch role — amber ghost style
                  GestureDetector(
                    onTap: () async {
                      await _storage.deleteAll();
                      if (context.mounted) context.go('/login');
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(KasaRadius.xl),
                        border: Border.all(
                          color: Colors.amber.shade600,
                          width: KasaBorders.button,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.swap_horiz,
                              size: 18, color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'SWITCH ACCOUNT',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.28,
                              color: Colors.amber.shade700,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Log out
                  KasaButton(
                    label: 'LOG OUT',
                    variant: KasaButtonVariant.primary,
                    leading: Icon(Icons.logout,
                        size: 18, color: cs.onPrimary),
                    onTap: _confirmLogout,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Version footer ────────────────────────────────────────────────
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Text(
                  'KASA v1.0.0',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: cs.kasaTextSub,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Detail row helper ─────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isFirst = false,
    this.valueStyle,
  });

  final String label;
  final String value;
  final bool isFirst;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: isFirst
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.kasaStroke, width: 2),
              ),
            ),
      padding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04,
              color: cs.kasaTextSub,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value.isNotEmpty ? value : '—',
              textAlign: TextAlign.right,
              style: valueStyle ??
                  GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
