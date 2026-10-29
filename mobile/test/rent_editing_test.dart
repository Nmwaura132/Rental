import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/properties/rent_editing.dart';

import 'support/kasa_test_fonts.dart';

class _Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return ResponseBody.fromString(jsonEncode({'rent_amount': '0', 'tenancy_updated': true}), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

const _units = [
  {'id': 1, 'unit_number': 'G1', 'rent_amount': '2500.00'},
  {'id': 2, 'unit_number': 'G2', 'rent_amount': '2500.00'},
  {'id': 3, 'unit_number': '1A', 'rent_amount': '2500.00'},
];

Future<_Server> _pump(WidgetTester tester, Widget child, {Size size = const Size(390, 844), double textScale = 1}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final server = _Server();
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'http://t'))..httpClientAdapter = server)],
    child: MaterialApp(theme: ThemeData(colorScheme: const ColorScheme.light()), home: child),
  ));
  await tester.pumpAndSettle();
  return server;
}

Widget _screen() => const EditRentsScreen(buildingName: 'Maria Goretti Apartments', units: _units);

void main() {
  setUpAll(loadKasaFonts);

  testWidgets('lists every house with its rent', (tester) async {
    await _pump(tester, _screen());
    expect(find.text('2500'), findsNWidgets(3));
  });

  testWidgets('saves only the houses changed', (tester) async {
    final server = await _pump(tester, _screen());
    await tester.enterText(find.byType(TextField).at(2), '3000');
    await tester.pump();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    expect(server.requests.map((r) => r.path), ['/api/v1/properties/units/2/set-rent/']);
  });

  testWidgets('sends the new amount', (tester) async {
    final server = await _pump(tester, _screen());
    await tester.enterText(find.byType(TextField).at(2), '3,000');
    await tester.pump();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    expect(server.requests.single.data, {'rent_amount': '3,000'});
  });

  testWidgets('shows what a changed rent was', (tester) async {
    await _pump(tester, _screen());
    await tester.enterText(find.byType(TextField).at(1), '3000');
    await tester.pump();
    expect(find.text('Was KES 2,500'), findsOneWidget);
  });

  testWidgets('one amount can be applied to every house', (tester) async {
    await _pump(tester, _screen());
    await tester.enterText(find.byType(TextField).first, '3000');
    await tester.pump();
    await tester.tap(find.text('Apply to all 3'));
    await tester.pump();
    expect(find.text('Save 3 changes'), findsOneWidget);
  });

  testWidgets('applying to all saves nothing until Save', (tester) async {
    final server = await _pump(tester, _screen());
    await tester.enterText(find.byType(TextField).first, '3000');
    await tester.pump();
    await tester.tap(find.text('Apply to all 3'));
    await tester.pump();
    expect(server.requests, isEmpty);
  });

  testWidgets('one house: says when a tenant is charged the new rent', (tester) async {
    await _pump(
      tester,
      Consumer(builder: (context, ref, _) => Scaffold(
        body: TextButton(
          onPressed: () => changeRent(context, ref, _units.first, hasTenant: true),
          child: const Text('open'),
        ),
      )),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('from their next bill'), findsOneWidget);
  });

  for (final width in [360.0, 320.0]) {
    testWidgets('edit rents fits at $width, text 30% larger', (tester) async {
      await _pump(tester, _screen(), size: Size(width, 700), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }
}
