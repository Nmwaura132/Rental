import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/user_role_provider.dart';

const _storage = FlutterSecureStorage();

/// Dev-only screen that bypasses login.
/// Writes a fake role + name to storage so the rest of the app
/// behaves as if the user logged in normally.
class DevPickerScreen extends ConsumerWidget {
  const DevPickerScreen({super.key});

  Future<void> _enter(BuildContext context, WidgetRef ref, String role) async {
    await _storage.write(key: 'access_token', value: 'dev-token-$role');
    await _storage.write(key: 'refresh_token', value: 'dev-refresh-$role');
    await _storage.write(key: 'user_role', value: role);
    await _storage.write(
        key: 'user_name',
        value: role == 'landlord' ? 'Dev Landlord' : 'Dev Tenant');
    await _storage.write(key: 'user_phone', value: '+254700000000');
    // Invalidate the cached role so MainShell re-reads it
    ref.invalidate(userRoleProvider);
    if (context.mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient (same as login)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App icon + name
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Icon(Icons.maps_home_work_rounded,
                            color: Colors.white, size: 56),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Kasa',
                        style: GoogleFonts.outfit(
                          textStyle: theme.textTheme.displaySmall,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.5)),
                        ),
                        child: const Text(
                          'DEV MODE — pick a view',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Landlord card
                  _RoleCard(
                    icon: Icons.home_work_rounded,
                    label: 'Landlord',
                    description:
                        'Dashboard, properties, tenants, invoices, reports',
                    color: const Color(0xFF64B5F6),
                    onTap: () => _enter(context, ref, 'landlord'),
                  ),

                  const SizedBox(height: 16),

                  // Tenant card
                  _RoleCard(
                    icon: Icons.person_rounded,
                    label: 'Tenant',
                    description: 'Balance, invoices, M-Pesa instructions, maintenance',
                    color: const Color(0xFF81C784),
                    onTap: () => _enter(context, ref, 'tenant'),
                  ),

                  const Spacer(),

                  // Hint to re-enable login later
                  Text(
                    'Replace DevPickerScreen with LoginScreen in router.dart when ready.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            splashColor: color.withValues(alpha: 0.15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                    ),
                    child: Icon(icon, color: color, size: 32),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      color: color.withValues(alpha: 0.7), size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
