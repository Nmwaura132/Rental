import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

const _storage = FlutterSecureStorage();
const _enabledKey = 'biometric_enabled';
const _askedKey = 'biometric_asked';
const _authenticatedAtKey = 'biometric_authenticated_at';

/// How long a fingerprint may stand in for the password before the password
/// itself is required again. The clock restarts on every password sign-in.
const biometricCredentialLifetime = Duration(days: 60);

/// What the router should do with a stored session.
enum SessionLockState {
  /// Nothing stored, or biometrics off — behave as normal.
  none,

  /// A credential is waiting behind the sensor.
  locked,

  /// The credential outlived [biometricCredentialLifetime] and has been
  /// discarded; the password is required.
  expired,
}

/// Why an unlock attempt failed, so callers can tell "try again" apart from
/// "this will never work here" and word the message accordingly.
enum BiometricFailure {
  /// Cancelled, timed out, or the sensor did not recognise the user.
  rejected,

  /// No hardware, or the OS reports the sensor as unusable right now.
  unavailable,

  /// Hardware exists but nothing is enrolled on it.
  notEnrolled,

  /// Too many failed attempts — the OS has locked the sensor out.
  lockedOut,
}

class BiometricException implements Exception {
  const BiometricException(this.failure, this.message);

  final BiometricFailure failure;
  final String message;

  @override
  String toString() => 'BiometricException($failure): $message';
}

class BiometricService {
  BiometricService(this._auth);

  final LocalAuthentication _auth;

  /// True only when the device has hardware AND something is enrolled on it.
  /// Both matter: a toggle that can never succeed should not be offered.
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.canCheckBiometrics;
    } on LocalAuthException {
      // An unreadable sensor and an absent one call for the same response:
      // don't offer biometric unlock.
      return false;
    }
  }

  Future<bool> isEnabled() async =>
      await _storage.read(key: _enabledKey) == 'true';

  Future<void> setEnabled({required bool enabled}) async {
    if (enabled) {
      await _storage.write(key: _enabledKey, value: 'true');
      await stampPasswordAuth();
    } else {
      await _storage.delete(key: _enabledKey);
      await _storage.delete(key: _authenticatedAtKey);
    }
  }

  /// Restarts the 60-day clock. Called whenever the password itself has been
  /// entered, since that is the thing the fingerprint is standing in for.
  Future<void> stampPasswordAuth() => _storage.write(
        key: _authenticatedAtKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );

  /// Whether the offer to turn biometrics on has already been made once.
  /// Declining is a real answer, so the offer is not repeated every login.
  Future<bool> hasBeenOffered() async =>
      await _storage.read(key: _askedKey) == 'true';

  Future<void> markOffered() async =>
      _storage.write(key: _askedKey, value: 'true');

  /// Ends the active session but keeps the refresh token that biometrics
  /// unlocks, so signing out still leaves a fingerprint way back in.
  ///
  /// WHY not wipe everything: a full clear destroys the very credential the
  /// sensor exists to unlock, which would make biometric sign-in impossible
  /// for exactly the people who turned it on. Turning the toggle off — or
  /// failing the sensor — still clears the lot.
  Future<void> endSessionKeepingCredential() async {
    await _storage.delete(key: 'access_token');
  }

  /// Whether a fingerprint can still get this device back into an account,
  /// whether or not an access token is currently live.
  Future<SessionLockState> lockState() async {
    if (!await isEnabled()) return SessionLockState.none;
    if (await _storage.read(key: 'refresh_token') == null) {
      return SessionLockState.none;
    }

    if (await _hasOutlivedPassword()) {
      // Drop the credential rather than merely hiding it, so an expired
      // enrolment cannot be revived by anything short of the password. The
      // preference itself survives: the user opted in, and re-entering the
      // password re-arms it without making them find the toggle again.
      await _storage.delete(key: 'refresh_token');
      await _storage.delete(key: 'access_token');
      return SessionLockState.expired;
    }

    return SessionLockState.locked;
  }

  Future<bool> _hasOutlivedPassword() async {
    final stamp = await _storage.read(key: _authenticatedAtKey);
    // A credential with no stamp predates this rule; treat it as due rather
    // than trusting it indefinitely.
    if (stamp == null) return true;

    final at = DateTime.tryParse(stamp);
    if (at == null) return true;

    return DateTime.now().toUtc().difference(at) > biometricCredentialLifetime;
  }

  /// Throws [BiometricException] rather than returning false so callers can
  /// tell a rejection (offer retry) from an unusable sensor (fall back to
  /// password) instead of guessing from a bare bool.
  Future<void> authenticate({required String reason}) async {
    final bool ok;
    try {
      ok = await _auth.authenticate(
        localizedReason: reason,
        // WHY biometricOnly: allowing the device PIN as fallback would let
        // anyone who knows the unlock code into the tenants' data, which
        // defeats a second factor on an already-unlocked phone.
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      throw BiometricException(_failureFor(e.code), e.description ?? e.code.name);
    }

    if (!ok) {
      throw const BiometricException(
        BiometricFailure.rejected,
        'Not recognised.',
      );
    }
  }

  // The plugin documents that codes may be added without a breaking change,
  // so this deliberately falls through to `rejected` rather than matching
  // exhaustively.
  BiometricFailure _failureFor(LocalAuthExceptionCode code) {
    switch (code) {
      case LocalAuthExceptionCode.noBiometricsEnrolled:
      case LocalAuthExceptionCode.noCredentialsSet:
        return BiometricFailure.notEnrolled;
      case LocalAuthExceptionCode.noBiometricHardware:
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
      case LocalAuthExceptionCode.uiUnavailable:
        return BiometricFailure.unavailable;
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return BiometricFailure.lockedOut;
      default:
        return BiometricFailure.rejected;
    }
  }
}

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(LocalAuthentication()),
);

final biometricAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricServiceProvider).isAvailable(),
);

final biometricEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricServiceProvider).isEnabled(),
);

/// Cleared on every cold start, so a stored session is unlocked once per app
/// launch rather than once per navigation.
final sessionUnlockedProvider = StateProvider<bool>((ref) => false);
