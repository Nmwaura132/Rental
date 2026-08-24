import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../navigation_key.dart';
import '../theme/kasa_tokens.dart';
import '../widgets/kasa_logo.dart';
import '../widgets/kasa_primitives.dart';
import 'biometric_service.dart';

const _storage = FlutterSecureStorage();

/// Covers the app with a lock screen on cold start when the user has turned
/// biometric unlock on and a session is already stored.
///
/// WHY a cover rather than a route: "keep me signed in" means the router sends
/// a returning user straight to /dashboard, so there is no login screen left to
/// hang this off. Wrapping MaterialApp's builder locks every route at once and
/// leaves the router's redirect logic alone.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate> {
  bool _locked = false;
  bool _checking = true;
  bool _prompting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decideLock();
  }

  Future<void> _decideLock() async {
    final service = ref.read(biometricServiceProvider);
    final hasSession = await _storage.read(key: 'access_token') != null;
    final enabled = hasSession && await service.isEnabled();

    if (!mounted) return;
    setState(() {
      _locked = enabled;
      _checking = false;
    });

    if (enabled) await _promptUnlock();
  }

  Future<void> _promptUnlock() async {
    if (_prompting) return;
    setState(() {
      _prompting = true;
      _error = null;
    });

    try {
      await ref
          .read(biometricServiceProvider)
          .authenticate(reason: 'Unlock Kasa');
      if (mounted) setState(() => _locked = false);
    } on BiometricException catch (e) {
      if (!mounted) return;
      // A sensor that can no longer work must not strand the user behind a
      // lock they cannot pass — drop them to password sign-in instead.
      if (e.failure == BiometricFailure.unavailable ||
          e.failure == BiometricFailure.notEnrolled) {
        await _signOut();
        return;
      }
      setState(() => _error = switch (e.failure) {
            BiometricFailure.lockedOut =>
              'Too many attempts. Use your password to sign in.',
            _ => 'Not recognised. Try again.',
          });
    } finally {
      if (mounted) setState(() => _prompting = false);
    }
  }

  Future<void> _signOut() async {
    await _storage.deleteAll();
    if (!mounted) return;
    setState(() => _locked = false);
    rootNavigatorKey.currentContext?.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    // WHY hold a blank frame: showing the dashboard for the instant it takes to
    // read storage would leak exactly what the lock exists to hide.
    if (_checking) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.kasaBg,
        child: const SizedBox.expand(),
      );
    }

    return Stack(
      children: [
        widget.child,
        if (_locked) _LockCover(
          error: _error,
          isPrompting: _prompting,
          onUnlock: _promptUnlock,
          onUsePassword: _signOut,
        ),
      ],
    );
  }
}

class _LockCover extends StatelessWidget {
  const _LockCover({
    required this.error,
    required this.isPrompting,
    required this.onUnlock,
    required this.onUsePassword,
  });

  final String? error;
  final bool isPrompting;
  final VoidCallback onUnlock;
  final VoidCallback onUsePassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Semantics(
      // Nothing behind the cover should be reachable by a screen reader while
      // the app is locked.
      scopesRoute: true,
      explicitChildNodes: true,
      child: Material(
        color: cs.kasaBg,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const KasaLockupStacked(markSize: 64),
                  const SizedBox(height: 32),
                  Icon(Icons.fingerprint_rounded, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text('Kasa is locked', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    error ?? 'Unlock with your fingerprint or face.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: error == null ? cs.onSurfaceVariant : cs.error,
                    ),
                  ),
                  const SizedBox(height: 28),
                  KasaButton(
                    label: 'Unlock',
                    isLoading: isPrompting,
                    onTap: isPrompting ? null : onUnlock,
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: onUsePassword,
                    child: const Text('Use password instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
