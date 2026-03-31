import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../../core/constants.dart';

const _storage = FlutterSecureStorage();

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = true; // default: stay logged in for 30 days

  @override
  void initState() {
    super.initState();
    _loadSavedPhone();
  }

  Future<void> _loadSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPhone = prefs.getString('saved_phone');
    if (savedPhone != null && mounted) {
      setState(() => _phoneCtrl.text = savedPhone);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      ));
      final resp = await dio.post('/api/v1/auth/login/', data: {
        'phone_number': _phoneCtrl.text.trim(),
        'password': _passCtrl.text,
      });

      if (_rememberMe) {
        // Store tokens — refresh token lasts 30 days on the server
        await _storage.write(key: 'access_token', value: resp.data['access']);
        await _storage.write(key: 'refresh_token', value: resp.data['refresh']);
        // Remember the phone number for next time
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_phone', _phoneCtrl.text.trim());
      } else {
        // Session-only: store tokens but clear saved phone
        await _storage.write(key: 'access_token', value: resp.data['access']);
        await _storage.write(key: 'refresh_token', value: resp.data['refresh']);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_phone');
      }

      await _storage.write(key: 'user_role', value: resp.data['role']);
      await _storage.write(key: 'user_name', value: resp.data['name']);
      await _storage.write(key: 'user_phone', value: resp.data['phone_number'] ?? '');

      if (mounted) context.go('/dashboard');
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.data is Map
            ? (e.response!.data['detail'] ??
                e.response!.data.values.first.toString())
            : 'Login failed. Check your credentials.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          reverse: true,
          child: Column(
            children: [
              const SizedBox(height: 48),
              const Icon(Icons.home_work_rounded, color: Colors.white, size: 64),
              const SizedBox(height: 8),
              Text('Rental Manager',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Smart Rental Platform',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70)),
              const SizedBox(height: 40),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Sign In', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('Enter your phone number and password',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone),
                          hintText: '+1234567890',
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Phone number is required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Password is required'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (v) =>
                                setState(() => _rememberMe = v ?? true),
                            visualDensity: VisualDensity.compact,
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _rememberMe = !_rememberMe),
                            child: const Text('Remember me for 30 days'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Sign In'),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => const _ForgotPasswordPage(),
                            ),
                          ),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForgotPasswordPage extends StatefulWidget {
  const _ForgotPasswordPage();

  @override
  State<_ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<_ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      ));

      await dio.post('/api/v1/auth/password-reset/', data: {
        'phone_number': _phoneCtrl.text.trim(),
        'new_password': _newPassCtrl.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password reset successfully. Please log in.')),
        );
        Navigator.of(context).pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        final raw = e.response?.data;
        final msg = raw is Map
            ? (raw['error'] ?? 'Reset failed. Try again.')
            : 'Reset failed. Check your connection.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg is List ? msg.join(', ') : msg.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter your phone number and a new password.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                  hintText: '+254XXXXXXXXX',
                ),
                validator: (v) => v == null || v.isEmpty
                    ? 'Phone number is required'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newPassCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureNew ? Icons.visibility : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPassCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) =>
                    v != _newPassCtrl.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _loading ? null : _reset,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Reset Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
