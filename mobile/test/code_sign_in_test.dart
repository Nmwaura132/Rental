import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/auth/login_screen.dart';

import 'support/kasa_test_fonts.dart';

class _Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return ResponseBody.fromString(jsonEncode({'message': 'ok'}), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

Future<_Server> _pump(WidgetTester tester, {Size size = const Size(390, 844), double textScale = 1.0}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  final server = _Server();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server;
  await tester.pumpWidget(ProviderScope(
    overrides: [publicDioProvider.overrideWithValue(dio)],
    child: const MaterialApp(home: LoginScreen()),
  ));
  await tester.pumpAndSettle();
  return server;
}

Future<void> _askForCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, '0712345678');
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKasaFonts);

  testWidgets('signing in starts with a code, not a password', (tester) async {
    await _pump(tester);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('the code is sent to the number in international form', (tester) async {
    final server = await _pump(tester);
    await _askForCode(tester);
    expect(server.requests.last.data, {'phone_number': '+254712345678'});
  });

  testWidgets('it asks for the code to the right endpoint', (tester) async {
    final server = await _pump(tester);
    await _askForCode(tester);
    expect(server.requests.last.path, '/api/v1/auth/login/request-code/');
  });

  testWidgets('once sent, it asks for the code', (tester) async {
    await _pump(tester);
    await _askForCode(tester);
    expect(find.text('Code'), findsOneWidget);
  });

  testWidgets('a new code can be asked for', (tester) async {
    await _pump(tester);
    await _askForCode(tester);
    expect(find.text('Send a new code'), findsOneWidget);
  });

  testWidgets('changing the number starts over', (tester) async {
    await _pump(tester);
    await _askForCode(tester);
    await tester.enterText(find.byType(TextFormField).first, '0712345679');
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('the password is still there as a backup', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('and the way back to a code', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with a code instead'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('a new landlord can find sign-up', (tester) async {
    await _pump(tester);
    expect(find.text('New landlord? Create an account'), findsOneWidget);
  });

  for (final width in [360.0, 320.0]) {
    testWidgets('fits at $width wide with text 30% larger, code showing', (tester) async {
      await _pump(tester, size: Size(width, 700), textScale: 1.3);
      await _askForCode(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits at $width wide with text 30% larger, password showing', (tester) async {
      await _pump(tester, size: Size(width, 700), textScale: 1.3);
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reset fits at $width wide with text 30% larger', (tester) async {
      await _pump(tester, size: Size(width, 700), textScale: 1.3);
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '0712345678');
      await tester.tap(find.text('Send Reset Code'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the main button stays above the keyboard', (tester) async {
    await _pump(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();
    final button = tester.getBottomLeft(find.text('Send code')).dy;
    expect(button < 844 - 300, isTrue);
  });
}
