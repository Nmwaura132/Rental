import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/core/widgets/kasa_primitives.dart';
import 'package:rental_manager/features/payments/record_payment_screen.dart';

import 'support/kasa_test_fonts.dart';

const _bill = <String, dynamic>{
  'id': 7,
  'tenant_name': 'Salome Wanjiru',
  'unit_number': '2A',
  'balance': '27500.00',
};

class _Server implements HttpClientAdapter {
  _Server({this.refuseWith});
  final String? refuseWith;
  Map<String, dynamic>? sent;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    sent = Map<String, dynamic>.from(o.data as Map);
    final status = refuseWith == null ? 201 : 400;
    return ResponseBody.fromString(
      jsonEncode(refuseWith == null ? {'id': 1} : {'error': refuseWith}),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

Widget _host(_Server server) {
  final dio = Dio()..httpClientAdapter = server;
  return ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: MaterialApp(
      home: RecordPaymentScreen(bill: _bill, onDone: () {}),
    ),
  );
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(server));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byType(KasaButton));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKasaFonts);

  testWidgets('M-Pesa is what it starts on', (tester) async {
    await _open(tester, _Server());
    expect(find.text('M-Pesa code'), findsOneWidget);
  });

  testWidgets('the amount starts as what the bill still owes', (tester) async {
    await _open(tester, _Server());
    expect(find.widgetWithText(TextField, '27500'), findsOneWidget);
  });

  testWidgets('M-Pesa cannot be saved without its code', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await _save(tester);
    expect(server.sent, isNull);
  });

  testWidgets('a missing code is explained', (tester) async {
    await _open(tester, _Server());
    await _save(tester);
    expect(find.text('Enter the code from the M-Pesa message.'), findsOneWidget);
  });

  testWidgets('the code is sent as M-Pesa', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await tester.enterText(find.byType(TextField).last, 'SIR4K7X2QP');
    await _save(tester);
    expect(server.sent, {
      'invoice': 7,
      'method': 'mpesa',
      'amount': 27500.0,
      'mpesa_receipt_number': 'SIR4K7X2QP',
    });
  });

  testWidgets('cash needs no reference', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(server.sent, {'invoice': 7, 'method': 'cash', 'amount': 27500.0});
  });

  testWidgets('paying over the bill says where the rest goes', (tester) async {
    await _open(tester, _Server());
    await tester.enterText(find.byType(TextField).first, '30000');
    await tester.pump();
    expect(find.textContaining('2,500 over this bill'), findsOneWidget);
  });

  testWidgets('what the server refuses is shown on the screen', (tester) async {
    await _open(tester, _Server(refuseWith: 'M-Pesa code SIR4K7X2QP has already been recorded.'));
    await tester.enterText(find.byType(TextField).last, 'SIR4K7X2QP');
    await _save(tester);
    expect(find.text('M-Pesa code SIR4K7X2QP has already been recorded.'), findsOneWidget);
  });

  testWidgets('it warns that the tenant is texted', (tester) async {
    await _open(tester, _Server());
    expect(find.textContaining('Salome gets a text receipt'), findsOneWidget);
  });

  testWidgets('it fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_Server()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
