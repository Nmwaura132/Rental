import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rental_manager/core/auth/biometric_service.dart';
import 'package:rental_manager/features/auth/login_screen.dart';

/// Stands in for the real sensor so the test never reaches a platform channel.
class _StubBiometricService extends BiometricService {
  _StubBiometricService({required this.succeeds}) : super(LocalAuthentication());

  final bool succeeds;

  @override
  Future<void> authenticate({required String reason}) async {
    if (!succeeds) {
      throw const BiometricException(
        BiometricFailure.rejected,
        'Not recognised.',
      );
    }
  }
}

Future<void> _pumpLocked(WidgetTester tester, {required bool succeeds}) async {
  FlutterSecureStorage.setMockInitialValues({
    'biometric_enabled': 'true',
    'refresh_token': 'stored-refresh',
  });
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        biometricServiceProvider.overrideWithValue(
          _StubBiometricService(succeeds: succeeds),
        ),
      ],
      child: const MaterialApp(home: LoginScreen(isLocked: true)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a locked session offers unlock instead of the password form',
      (tester) async {
    await _pumpLocked(tester, succeeds: false);

    expect(find.text('Phone Number'), findsNothing);
  });

  testWidgets('a locked session can fall back to password sign-in',
      (tester) async {
    await _pumpLocked(tester, succeeds: false);

    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    expect(find.text('Phone Number'), findsOneWidget);
  });

  testWidgets('a rejected fingerprint explains itself rather than failing silently',
      (tester) async {
    await _pumpLocked(tester, succeeds: false);

    expect(find.text('Not recognised. Tap to try again.'), findsOneWidget);
  });

  testWidgets('choosing the password fallback keeps biometrics turned on',
      (tester) async {
    await _pumpLocked(tester, succeeds: false);

    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    expect(
      await const FlutterSecureStorage().read(key: 'biometric_enabled'),
      'true',
    );
  });
}
