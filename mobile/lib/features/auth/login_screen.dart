import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/kasa_logo.dart';

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
      setState(() => _phoneCtrl.text = toLocalKenyanDigits(savedPhone));
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
      final phone = normalizeKenyanPhone(_phoneCtrl.text);
      final dio = ref.read(publicDioProvider);
      final resp = await dio.post('/api/v1/auth/login/', data: {
        'phone_number': phone,
        'password': _passCtrl.text,
      });

      if (_rememberMe) {
        // Store tokens — refresh token lasts 30 days on the server
        await _storage.write(key: 'access_token', value: resp.data['access']);
        await _storage.write(key: 'refresh_token', value: resp.data['refresh']);
        // Remember the phone number for next time
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_phone', phone);
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
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.kasaBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // WHY a plain rise-and-fade instead of the previous elastic
                      // bounce: the mark is a wordmark, and overshoot on type reads
                      // as a toy. Entrance only, nothing looping.
                      const _RiseIn(
                        child: KasaLockupStacked(markSize: 72),
                      ),
                      const SizedBox(height: 12),
                      _RiseIn(
                        delayMs: 60,
                        child: Text(
                          'Rent, sorted.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),

                      _RiseIn(
                        delayMs: 120,
                        child: KasaCard(
                          padding: const EdgeInsets.all(24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Sign In',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 20),

                                TextFormField(
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(12),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Phone Number',
                                    prefixIcon: Icon(Icons.phone_rounded),
                                    prefixText: '+254 ',
                                    hintText: '712 345 678',
                                  ),
                                  validator: validateKenyanPhone,
                                ),
                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: _passCtrl,
                                  obscureText: _obscure,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded),
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      tooltip: _obscure
                                          ? 'Show password'
                                          : 'Hide password',
                                    ),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Password is required'
                                      : null,
                                ),
                                const SizedBox(height: 8),

                                // WHY the whole row toggles: a bare 24px checkbox
                                // is under the 44px touch-target minimum.
                                InkWell(
                                  onTap: () =>
                                      setState(() => _rememberMe = !_rememberMe),
                                  borderRadius:
                                      BorderRadius.circular(KasaRadius.sm),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: Checkbox(
                                            value: _rememberMe,
                                            onChanged: (v) => setState(
                                                () => _rememberMe = v ?? true),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text('Keep me signed in',
                                            style: theme.textTheme.bodyMedium),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                KasaButton(
                                  label: 'Sign In',
                                  isLoading: _loading,
                                  onTap: _loading ? null : _login,
                                ),
                                const SizedBox(height: 4),

                                TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      fullscreenDialog: true,
                                      builder: (_) => const _ForgotPasswordPage(),
                                    ),
                                  ),
                                  child: const Text('Forgot password?'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Entrance animation: rise and fade, once, on first build.
class _RiseIn extends StatelessWidget {
  const _RiseIn({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) => Transform.translate(
        offset: Offset(0, 16 * (1 - val)),
        child: Opacity(opacity: val.clamp(0.0, 1.0), child: child),
      ),
      child: child,
    );
  }
}

class _ForgotPasswordPage extends ConsumerStatefulWidget {
  const _ForgotPasswordPage();

  @override
  ConsumerState<_ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<_ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _loading = false;
  bool _otpRequested = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final dio = ref.read(publicDioProvider);
      await dio.post('/api/v1/auth/password-reset/request/', data: {
        'phone_number': normalizeKenyanPhone(_phoneCtrl.text),
      });
      if (mounted) {
        setState(() => _otpRequested = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('If the number is registered, a reset code was sent.')),
        );
      }
    } on DioException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not request a reset code. Try again.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final dio = ref.read(publicDioProvider);

      await dio.post('/api/v1/auth/password-reset/', data: {
        'phone_number': normalizeKenyanPhone(_phoneCtrl.text),
        'otp': _otpCtrl.text.trim(),
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
              Text(
                'Enter your phone number to receive a one-time reset code.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                  prefixText: '+254 ',
                  hintText: '712 345 678',
                ),
                validator: validateKenyanPhone,
              ),
              const SizedBox(height: 16),
              if (_otpRequested) ...[
                TextFormField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Reset Code',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                  validator: (v) =>
                      v == null || v.length != 6 ? 'Enter the 6-digit code' : null,
                ),
                const SizedBox(height: 16),
              ],
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
                  if (!_otpRequested) return null;
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
                    _otpRequested && v != _newPassCtrl.text
                        ? 'Passwords do not match'
                        : null,
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed:
                    _loading ? null : (_otpRequested ? _reset : _requestOtp),
                child: _loading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.onPrimary,
                            strokeWidth: 2),
                      )
                    : Text(_otpRequested ? 'Reset Password' : 'Send Reset Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
