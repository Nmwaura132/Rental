import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/auth/signup_screen.dart';
import 'package:rental_manager/features/dashboard/setup_checklist.dart';
import 'package:rental_manager/features/payments/payment_methods_screen.dart';

import 'support/kasa_test_fonts.dart';

/// Answers every request with [body], and remembers what was asked.
class _Server implements HttpClientAdapter {
  _Server(this.body);
  final Object body;
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

Future<_Server> _pump(
  WidgetTester tester,
  Widget child, {
  Object body = const {},
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final server = _Server(body);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      publicDioProvider.overrideWithValue(dio),
      ...overrides,
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
  return server;
}

const _kcbConnecting = {
  'id': 1,
  'kind': 'kcb_paybill',
  'kind_display': 'KCB paybill',
  'status': 'connecting',
  'number': '522522',
  'account_prefix': '',
};

const _bank = {
  'id': 2,
  'kind': 'bank',
  'kind_display': 'Bank account',
  'status': 'active',
  'bank_name': 'KCB',
  'account_number': '1234567890',
};

void main() {
  setUpAll(loadKasaFonts);

  group('signing up', () {
    testWidgets('starts with the phone number', (tester) async {
      await _pump(tester, const SignupScreen());
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('asks for nothing else until a code is sent', (tester) async {
      await _pump(tester, const SignupScreen());
      expect(find.text('First name'), findsNothing);
    });

    testWidgets('sends the code to the number in international form', (tester) async {
      final server = await _pump(tester, const SignupScreen());
      await tester.enterText(find.byType(TextFormField).first, '0712345678');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(server.requests.last.data, {'phone_number': '+254712345678'});
    });

    testWidgets('then asks for the code, name and password', (tester) async {
      await _pump(tester, const SignupScreen());
      await tester.enterText(find.byType(TextFormField).first, '0712345678');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('does not send a code for a number that is not Kenyan', (tester) async {
      final server = await _pump(tester, const SignupScreen());
      await tester.enterText(find.byType(TextFormField).first, '12');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(server.requests, isEmpty);
    });
  });

  group('how tenants pay', () {
    testWidgets('invites a first method when there is none', (tester) async {
      await _pump(tester, const PaymentMethodsScreen(), body: {'results': []});
      expect(find.text('No payment method yet'), findsOneWidget);
    });

    testWidgets('shows a KCB paybill as still connecting', (tester) async {
      await _pump(tester, const PaymentMethodsScreen(), body: {'results': [_kcbConnecting]});
      expect(find.text('Connecting'), findsOneWidget);
    });

    testWidgets('explains what connecting means', (tester) async {
      await _pump(tester, const PaymentMethodsScreen(), body: {'results': [_kcbConnecting]});
      expect(find.text('Connecting your KCB paybill'), findsOneWidget);
    });

    testWidgets('says what a tenant is told for a bank account', (tester) async {
      await _pump(tester, const PaymentMethodsScreen(), body: {'results': [_bank]});
      expect(find.text('KCB · 1234567890'), findsOneWidget);
    });

    testWidgets('offers every kind of method to add', (tester) async {
      await _pump(tester, const PaymentMethodsScreen(), body: {'results': []});
      await tester.tap(find.text('Add a payment method'));
      await tester.pumpAndSettle();
      for (final kind in ['KCB paybill', 'Other paybill', 'Till number', 'Bank account', 'Cash']) {
        expect(find.text(kind), findsOneWidget);
      }
    });

    testWidgets('a till asks for no account prefix', (tester) async {
      await _pump(tester, const PaymentMethodsScreen(), body: {'results': []});
      await tester.tap(find.text('Add a payment method'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Till number'));
      await tester.pumpAndSettle();
      expect(find.text('Before the house number (optional)'), findsNothing);
    });

    testWidgets('a paybill can take the bank account before the house', (tester) async {
      await _pump(tester, const PaymentMethodsScreen(), body: {'results': []});
      await tester.tap(find.text('Add a payment method'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other paybill'));
      await tester.pumpAndSettle();
      expect(find.text('Before the house number (optional)'), findsOneWidget);
    });
  });

  group('the set-up checklist', () {
    Widget host(int units) => Scaffold(body: ListView(children: [SetupChecklist(totalUnits: units)]));

    testWidgets('lists both steps for a new landlord', (tester) async {
      await _pump(tester, host(0), overrides: [
        paymentAccountsProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
      ]);
      expect(find.text('0 of 2 done'), findsOneWidget);
    });

    testWidgets('ticks the building once it has units', (tester) async {
      await _pump(tester, host(10), overrides: [
        paymentAccountsProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
      ]);
      expect(find.text('1 of 2 done'), findsOneWidget);
    });

    testWidgets('goes away once both are done', (tester) async {
      await _pump(tester, host(10), overrides: [
        paymentAccountsProvider.overrideWith((ref) async => [_bank]),
      ]);
      expect(find.text('Get set up'), findsNothing);
    });
  });

  group('small phones and large text', () {
    for (final width in [360.0, 320.0]) {
      testWidgets('sign-up fits at $width wide with text 30% larger', (tester) async {
        await _pump(tester, const SignupScreen(), size: Size(width, 700), textScale: 1.3);
        await tester.enterText(find.byType(TextFormField).first, '0712345678');
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('payment methods fit at $width wide with text 30% larger', (tester) async {
        await _pump(tester, const PaymentMethodsScreen(),
            body: {'results': [_kcbConnecting, _bank]}, size: Size(width, 700), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the checklist fits at $width wide with text 30% larger', (tester) async {
        await _pump(tester, host(0),
            overrides: [paymentAccountsProvider.overrideWith((ref) async => <Map<String, dynamic>>[])],
            size: Size(width, 700),
            textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Widget host(int units) => Scaffold(body: ListView(children: [SetupChecklist(totalUnits: units)]));
