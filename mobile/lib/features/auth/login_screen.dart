import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/biometric_pulse.dart';
import '../../core/auth/biometric_service.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/kasa_logo.dart';

const _storage = FlutterSecureStorage();

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.isLocked = false,
    this.hasExpired = false,
  });

  /// Set by the router when a stored session is waiting behind a biometric
  /// check, which turns this screen into an unlock screen.
  final bool isLocked;

  /// Set by the router when a biometric credential was discarded for outliving
  /// [biometricCredentialLifetime], so the screen can say why the password is
  /// suddenly being asked for again.
  final bool hasExpired;

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

  late bool _isLocked = widget.isLocked;

  /// A sealed credential still exists even while the password form is showing,
  /// so the user can switch back without having thrown anything away.
  late bool _canUseBiometrics = widget.isLocked;

  BiometricPulseState _pulse = BiometricPulseState.idle;
  String? _unlockError;

  @override
  void initState() {
    super.initState();
    _loadSavedPhone();
    // Go straight to the sensor — making the user tap first only adds a step
    // to something they opened the app intending to do.
    if (_isLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  Future<void> _unlock() async {
    if (_pulse == BiometricPulseState.scanning) return;
    setState(() {
      _pulse = BiometricPulseState.scanning;
      _unlockError = null;
    });

    try {
      await ref
          .read(biometricServiceProvider)
          .authenticate(reason: 'Unlock Kasa');

      // Signing out cleared the access token but kept the refresh token, so
      // the session has to be minted back before the app is usable.
      if (await _storage.read(key: 'access_token') == null) {
        final restored = await _restoreSession();
        if (!restored) {
          if (!mounted) return;
          // The refresh token is dead, so there is nothing left to unlock —
          // the credential goes with it.
          await _forgetBiometrics();
          if (mounted) {
            setState(() => _unlockError =
                'Session expired. Sign in with your password.');
          }
          return;
        }
      }

      if (!mounted) return;
      setState(() => _pulse = BiometricPulseState.success);
      ref.read(sessionUnlockedProvider.notifier).state = true;
      // Let the ring finish closing before the screen changes under it.
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (mounted) context.go('/dashboard');
    } on BiometricException catch (e) {
      if (!mounted) return;
      // A sensor that can no longer work must not strand the user behind a
      // check they cannot pass — drop them to the password form instead.
      if (e.failure == BiometricFailure.unavailable ||
          e.failure == BiometricFailure.notEnrolled) {
        await _forgetBiometrics();
        return;
      }
      setState(() {
        _pulse = BiometricPulseState.error;
        _unlockError = switch (e.failure) {
          BiometricFailure.lockedOut =>
            'Too many attempts. Sign in with your password.',
          _ => 'Not recognised. Tap to try again.',
        };
      });
    }
  }

  /// Trades the kept refresh token for a live access token. Returns false when
  /// the refresh token has expired or been revoked server-side, which is the
  /// one case where biometrics cannot help and the password is required.
  Future<bool> _restoreSession() async {
    final refresh = await _storage.read(key: 'refresh_token');
    if (refresh == null) return false;

    try {
      final resp = await ref.read(publicDioProvider).post(
            '/api/v1/auth/token/refresh/',
            data: {'refresh': refresh},
          );
      await _storage.write(key: 'access_token', value: resp.data['access']);
      // Backend rotates and blacklists on refresh, so the new token has to
      // replace the old one or the next refresh fails.
      final rotated = resp.data['refresh'];
      if (rotated != null) {
        await _storage.write(key: 'refresh_token', value: rotated);
      }
      return true;
    } on DioException {
      return false;
    }
  }

  /// Swaps the unlock panel for the sign-in form without touching the stored
  /// credential, so the user can switch back and forth freely. Only a sensor
  /// that has genuinely stopped working discards anything — see [_forgetBiometrics].
  void _showPasswordForm() {
    setState(() {
      _isLocked = false;
      _pulse = BiometricPulseState.idle;
      _unlockError = null;
    });
  }

  void _showUnlockPanel() {
    setState(() {
      _isLocked = true;
      _pulse = BiometricPulseState.idle;
      _unlockError = null;
    });
    _unlock();
  }

  /// For a sensor that can no longer work. Leaving the setting on would seal
  /// the session again on the next launch and loop the user right back here,
  /// so the enrolment and the credential both go.
  Future<void> _forgetBiometrics() async {
    await ref.read(biometricServiceProvider).setEnabled(enabled: false);
    ref.invalidate(biometricEnabledProvider);
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');

    if (!mounted) return;
    setState(() {
      _isLocked = false;
      _canUseBiometrics = false;
      _pulse = BiometricPulseState.idle;
      _unlockError = null;
    });
  }

  /// Offers biometric unlock once, the first time someone signs in on a device
  /// that supports it. Declining is remembered so it is not asked again.
  Future<void> _maybeOfferBiometrics() async {
    final service = ref.read(biometricServiceProvider);
    if (await service.hasBeenOffered()) return;
    if (!await service.isAvailable()) return;
    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fingerprint_rounded, size: 40),
        title: const Text('Unlock with biometrics?'),
        content: const Text(
          'Use your fingerprint or face to open Kasa next time, instead of '
          'typing your password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );

    // Mark it asked either way: "no" is an answer, and re-asking every login
    // would be nagging.
    await service.markOffered();
    if (accepted != true) return;

    try {
      await service.authenticate(reason: 'Confirm to turn on biometric unlock');
      await service.setEnabled(enabled: true);
      ref.invalidate(biometricEnabledProvider);
    } on BiometricException {
      // Enrolment failed, so leave it off. The Profile toggle remains as a
      // second chance rather than blocking sign-in over it.
    }
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

      // Signing in with a password IS the check, so this session is already
      // open — don't make them prove themselves twice on the way to /dashboard.
      ref.read(sessionUnlockedProvider.notifier).state = true;

      // The password is what the fingerprint stands in for, so entering it
      // restarts the 60-day window for anyone already enrolled.
      final service = ref.read(biometricServiceProvider);
      if (await service.isEnabled()) await service.stampPasswordAuth();

      await _maybeOfferBiometrics();

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

                      if (_isLocked)
                        _RiseIn(
                          delayMs: 120,
                          child: _UnlockPanel(
                            pulse: _pulse,
                            error: _unlockError,
                            onUnlock: _unlock,
                            onUsePassword: _showPasswordForm,
                          ),
                        )
                      else
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

                                // Being asked for a password after weeks of
                                // fingerprints looks like a fault unless the
                                // reason is stated.
                                if (widget.hasExpired) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.schedule_rounded,
                                          size: 18, color: cs.onSurfaceVariant),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'It has been 60 days since you last '
                                          'used your password. Enter it once to '
                                          'turn your fingerprint back on.',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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

                                // The way back. Without it, "Use password
                                // instead" is a one-way door for anyone who
                                // taps it by mistake.
                                if (_canUseBiometrics)
                                  TextButton.icon(
                                    onPressed: _showUnlockPanel,
                                    icon: const Icon(Icons.fingerprint_rounded,
                                        size: 20),
                                    label: const Text('Use biometrics'),
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

/// Shown in place of the sign-in form when a stored session is waiting behind
/// a biometric check.
class _UnlockPanel extends StatelessWidget {
  const _UnlockPanel({
    required this.pulse,
    required this.error,
    required this.onUnlock,
    required this.onUsePassword,
  });

  final BiometricPulseState pulse;
  final String? error;
  final VoidCallback onUnlock;
  final VoidCallback onUsePassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isScanning = pulse == BiometricPulseState.scanning;

    return KasaCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Welcome back', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          Center(
            child: BiometricPulse(
              state: pulse,
              onTap: isScanning ? null : onUnlock,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            error ??
                switch (pulse) {
                  BiometricPulseState.scanning => 'Waiting for your fingerprint…',
                  BiometricPulseState.success => 'Unlocked',
                  _ => 'Tap to unlock with your fingerprint or face.',
                },
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: error == null ? cs.onSurfaceVariant : cs.error,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onUsePassword,
            child: const Text('Use password instead'),
          ),
        ],
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
