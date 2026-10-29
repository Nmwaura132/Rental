import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/notifications/message_tenants_screen.dart';
import 'package:rental_manager/features/payments/send_bills_card.dart';

import 'support/kasa_test_fonts.dart';

/// Answers by path; remembers each request.
class _Server implements HttpClientAdapter {
  _Server(this.routes);
  final Map<String, Object> routes;
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final body = routes['${o.method} ${o.path}'] ?? routes[o.path] ?? const {'results': []};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

Future<_Server> _pump(WidgetTester tester, Widget child, Map<String, Object> routes,
    {Size size = const Size(390, 844), double textScale = 1.0}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final server = _Server(routes);
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'http://t'))..httpClientAdapter = server)],
    child: MaterialApp(theme: ThemeData(colorScheme: const ColorScheme.light()), home: child),
  ));
  await tester.pumpAndSettle();
  return server;
}

const _billsUrl = '/api/v1/payments/invoices/send-month/';
const _msgUrl = '/api/v1/notifications/message-tenants/';

Widget _card() => const Scaffold(body: SingleChildScrollView(child: SendBillsCard()));

void main() {
  setUpAll(loadKasaFonts);

  group('send bills now', () {
    testWidgets('names the coming month', (tester) async {
      await _pump(tester, _card(), {'GET $_billsUrl': {'period': '2026-11-01', 'tenancies': 10, 'already_sent': 0}});
      expect(find.text('Send November bills now'), findsOneWidget);
    });

    testWidgets('says how many tenants', (tester) async {
      await _pump(tester, _card(), {'GET $_billsUrl': {'period': '2026-11-01', 'tenancies': 10, 'already_sent': 0}});
      expect(find.textContaining('10 tenants to bill'), findsOneWidget);
    });

    testWidgets('goes away once every bill is sent', (tester) async {
      await _pump(tester, _card(), {'GET $_billsUrl': {'period': '2026-11-01', 'tenancies': 10, 'already_sent': 10}});
      expect(find.textContaining('November'), findsNothing);
    });

    testWidgets('asks before sending', (tester) async {
      final server = await _pump(tester, _card(), {
        'GET $_billsUrl': {'period': '2026-11-01', 'tenancies': 10, 'already_sent': 0},
      });
      await tester.tap(find.text('Send November bills now'));
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('sends when confirmed', (tester) async {
      final server = await _pump(tester, _card(), {
        'GET $_billsUrl': {'period': '2026-11-01', 'tenancies': 10, 'already_sent': 0},
        'POST $_billsUrl': {'period': '2026-11-01', 'sent': 10, 'already_sent': 0},
      });
      await tester.tap(find.text('Send November bills now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send bills'));
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.method == 'POST').single.path, _billsUrl);
    });
  });

  group('message tenants', () {
    final routes = <String, Object>{'GET $_msgUrl': {'recipients': 10}, 'POST $_msgUrl': {'sent': 10}};

    testWidgets('starts with all tenants', (tester) async {
      await _pump(tester, const MessageTenantsScreen(), routes);
      expect(find.text('All my tenants'), findsOneWidget);
    });

    testWidgets('cannot send an empty message', (tester) async {
      await _pump(tester, const MessageTenantsScreen(), routes);
      await tester.tap(find.text('Send to 10 tenants'));
      await tester.pumpAndSettle();
      expect(find.text('Send to 10 tenants?'), findsNothing);
    });

    testWidgets('sends what was typed, after asking', (tester) async {
      final server = await _pump(tester, const MessageTenantsScreen(), routes);
      await tester.enterText(find.byType(TextField), 'Water off Saturday 9am to 1pm.');
      await tester.pump();
      await tester.tap(find.text('Send to 10 tenants'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.method == 'POST').single.data, {'message': 'Water off Saturday 9am to 1pm.'});
    });

    testWidgets('a long message is shown as more than one SMS', (tester) async {
      await _pump(tester, const MessageTenantsScreen(), routes);
      await tester.enterText(find.byType(TextField), 'x' * 200);
      await tester.pump();
      expect(find.text('2 SMS each'), findsOneWidget);
    });
  });

  group('small phones and large text', () {
    for (final width in [360.0, 320.0]) {
      testWidgets('send bills fits at $width, text 30% larger', (tester) async {
        await _pump(tester, _card(), {'GET $_billsUrl': {'period': '2026-11-01', 'tenancies': 10, 'already_sent': 3}},
            size: Size(width, 700), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('message tenants fits at $width, text 30% larger', (tester) async {
        await _pump(tester, const MessageTenantsScreen(), {'GET $_msgUrl': {'recipients': 10}},
            size: Size(width, 700), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
