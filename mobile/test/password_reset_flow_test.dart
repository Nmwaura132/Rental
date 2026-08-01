import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/auth/login_screen.dart';

void main() {
  testWidgets('password reset requests an OTP and submits the new password',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final paths = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          paths.add(options.path);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'message': 'ok'},
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [publicDioProvider.overrideWithValue(dio)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    final forgotButton = find.widgetWithText(TextButton, 'Forgot password?');
    await tester.ensureVisible(forgotButton);
    await tester.tap(forgotButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone Number'),
      '+254700111000',
    );
    await tester.tap(find.text('Send Reset Code'));
    await tester.pumpAndSettle();

    expect(find.text('Reset Code'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reset Code'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New Password'),
      'RotatedLandlord@Test2',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'RotatedLandlord@Test2',
    );
    final resetButton = find.widgetWithText(ElevatedButton, 'Reset Password');
    await tester.ensureVisible(resetButton);
    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    expect(paths, [
      '/api/v1/auth/password-reset/request/',
      '/api/v1/auth/password-reset/',
    ]);
  });
}
