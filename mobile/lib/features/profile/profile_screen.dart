import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/utils/api_error.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/providers/server_url_provider.dart';

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

  void _showServerUrlDialog() {
    final currentUrl = ref.read(serverUrlProvider);
    final ctrl = TextEditingController(text: currentUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'API Base URL',
            hintText: 'http://192.168.1.x:8020',
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(serverUrlProvider.notifier).state = ctrl.text.trim();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Server URL updated')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
    final serverUrl = ref.watch(serverUrlProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          // User info header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (_phone.isNotEmpty)
                  Text(_phone,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                if (_role.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Chip(
                    label: Text(_role.toUpperCase()),
                    backgroundColor:
                        theme.colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Theme section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Appearance',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.palette_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Theme',
                        style: theme.textTheme.bodyLarge),
                  ),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto, size: 18),
                          label: Text('Auto')),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode, size: 18),
                          label: Text('Light')),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode, size: 18),
                          label: Text('Dark')),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (sel) =>
                        ref.read(themeModeProvider.notifier).setMode(sel.first),
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Settings section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Settings',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Server URL'),
                  subtitle: Text(
                    serverUrl,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: _showServerUrlDialog,
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change Password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showChangePasswordDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Logout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
            ),
          ),
          const SizedBox(height: 32),

          // App version
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('About',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.home_work_rounded),
              title: const Text('Rental Manager'),
              subtitle: const Text('Version 1.0.0'),
              trailing: Icon(Icons.verified_outlined,
                  color: theme.colorScheme.primary, size: 18),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
