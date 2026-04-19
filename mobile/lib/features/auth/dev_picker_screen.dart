import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/providers/user_role_provider.dart';
import '../../core/widgets/kasa_logo.dart';
import '../../core/providers/server_url_provider.dart';

const _storage = FlutterSecureStorage();

/// Dev-only screen — bypasses the login form and signs in automatically
/// using the credentials defined in AppConstants (sourced from .env).
/// Replace GoRoute('/login') with LoginScreen when ready for production.
class DevPickerScreen extends ConsumerStatefulWidget {
  const DevPickerScreen({super.key});

  @override
  ConsumerState<DevPickerScreen> createState() => _DevPickerScreenState();
}

class _DevPickerScreenState extends ConsumerState<DevPickerScreen> {
  bool _loading = false;
  String? _loadingRole; // 'landlord' | 'tenant'

  Future<void> _loginAs(String role) async {
    setState(() {
      _loading = true;
      _loadingRole = role;
    });

    final phone = role == 'landlord'
        ? AppConstants.devLandlordPhone
        : AppConstants.devTenantPhone;
    final password = role == 'landlord'
        ? AppConstants.devLandlordPassword
        : AppConstants.devTenantPassword;

    try {
      final baseUrl = ref.read(serverUrlProvider);
      final dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      ));

      final resp = await dio.post('/api/v1/auth/login/', data: {
        'phone_number': phone,
        'password': password,
      });

      await _storage.write(key: 'access_token', value: resp.data['access']);
      await _storage.write(key: 'refresh_token', value: resp.data['refresh']);
      await _storage.write(key: 'user_role', value: resp.data['role']);
      await _storage.write(key: 'user_name', value: resp.data['name']);
      await _storage.write(
          key: 'user_phone', value: resp.data['phone_number'] ?? phone);

      ref.invalidate(userRoleProvider);
      if (mounted) context.go('/dashboard');
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.data is Map
            ? (e.response!.data['detail'] ??
                e.response!.data.values.first.toString())
            : 'Login failed. Check the dev credentials.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() { _loading = false; _loadingRole = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      const KasaLockupStacked(markSize: 56),
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
                    sublabel: 'Landlord Owner',
                    description:
                        'Dashboard · Properties · Tenants · Invoices · Reports',
                    color: const Color(0xFF64B5F6),
                    loading: _loadingRole == 'landlord' && _loading,
                    disabled: _loading,
                    onTap: () => _loginAs('landlord'),
                  ),

                  const SizedBox(height: 16),

                  // Tenant card
                  _RoleCard(
                    icon: Icons.person_rounded,
                    label: 'Tenant',
                    sublabel: 'Nelson Mwaura · Unit 201, Whitty',
                    description:
                        'Balance · Invoices · M-Pesa instructions · Maintenance',
                    color: const Color(0xFF81C784),
                    loading: _loadingRole == 'tenant' && _loading,
                    disabled: _loading,
                    onTap: () => _loginAs('tenant'),
                  ),

                  const Spacer(),

                  Text(
                    'Swap DevPickerScreen → LoginScreen in router.dart before release.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
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
    required this.sublabel,
    required this.description,
    required this.color,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final String description;
  final Color color;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: disabled && !loading ? 0.04 : 0.08),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: disabled ? null : onTap,
            splashColor: color.withValues(alpha: 0.15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: color.withValues(alpha: disabled && !loading ? 0.15 : 0.35)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                    ),
                    child: loading
                        ? Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: color),
                            ),
                          )
                        : Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: disabled && !loading
                                ? color.withValues(alpha: 0.4)
                                : color,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          sublabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!loading)
                    Icon(Icons.arrow_forward_ios_rounded,
                        color: color.withValues(alpha: disabled ? 0.2 : 0.7),
                        size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
