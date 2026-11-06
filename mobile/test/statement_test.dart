import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/payments/statement_screen.dart';

import 'support/kasa_test_fonts.dart';

Map<String, dynamic> _row(String unit, String tenant, {String paid = '27700.00', String balance = '0.00'}) => {
      'unit': unit,
      'tenant': tenant,
      'rent_paid': '25000.00',
      'water_previous': '0.00',
      'water_current': '11.00',
      'water_units': '11.00',
      'water_price': '200.00',
      'water_billed': '2200.00',
      'water_paid': '2200.00',
      'service_billed': '500.00',
      'service_paid': '500.00',
      'other_billed': '0',
      'other_paid': '0',
      'billed': '27700.00',
      'paid': paid,
      'balance': balance,
      'paid_via': 'M-Pesa UK4S88RZHZ',
    };

Map<String, dynamic> _totals(String billed, String paid, String balance) => {
      'rent_paid': '25000.00',
      'water_units': '11.00',
      'water_billed': '2200.00',
      'water_paid': '2200.00',
      'service_paid': '500.00',
      'other_paid': '0',
      'billed': billed,
      'paid': paid,
      'balance': balance,
    };

final _months = [
  {
    'month': '2026-10',
    'label': 'October 2026',
    'rows': [_row('G1', 'Margaret Wanjiru', paid: '25700.00', balance: '2000.00')],
    'totals': _totals('27700.00', '25700.00', '2000.00'),
  },
  {
    'month': '2026-11',
    'label': 'November 2026',
    'rows': [_row('2A', 'Salome Njeri')],
    'totals': _totals('27700.00', '27700.00', '0'),
  },
];

class _Server implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    final body = o.path.contains('properties')
        ? {'count': 1, 'next': null, 'results': [{'id': 1, 'name': 'Maria Goretti Apartments'}]}
        : {'property': 'Maria Goretti Apartments', 'months': _months};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

Future<void> _open(WidgetTester tester, {Size size = const Size(390, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(Dio()..httpClientAdapter = _Server())],
    child: const MaterialApp(home: StatementScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKasaFonts);

  testWidgets('it lists the newest month first', (tester) async {
    await _open(tester);
    final nov = tester.getTopLeft(find.text('November 2026').last).dy;
    final oct = tester.getTopLeft(find.text('October 2026').last).dy;
    expect(nov < oct, isTrue);
  });

  testWidgets('a house shows its tenant', (tester) async {
    await _open(tester);
    expect(find.text('2A · Salome Njeri'), findsOneWidget);
  });

  testWidgets('a house shows the water working', (tester) async {
    await _open(tester);
    expect(find.text('Water 0 → 11: 11 units × 200 = 2,200'), findsNWidgets(2));
  });

  testWidgets('a house shows how it was paid', (tester) async {
    await _open(tester);
    expect(find.text('Paid 27,700 of 27,700 · M-Pesa UK4S88RZHZ'), findsOneWidget);
  });

  testWidgets('a house that owes says how much', (tester) async {
    await _open(tester);
    expect(find.text('Owes 2,000'), findsOneWidget);
  });

  testWidgets('picking a month shows only that month', (tester) async {
    await _open(tester);
    await tester.tap(find.text('November 2026').first);
    await tester.pumpAndSettle();
    expect(find.text('G1 · Margaret Wanjiru'), findsNothing);
  });

  testWidgets('the totals follow the month picked', (tester) async {
    await _open(tester);
    await tester.tap(find.text('November 2026').first);
    await tester.pumpAndSettle();
    expect(find.text('KES 0'), findsOneWidget);
  });

  testWidgets('it offers the Excel download', (tester) async {
    await _open(tester);
    expect(find.text('Download Excel'), findsOneWidget);
  });

  testWidgets('it fits a narrow phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester, size: const Size(320, 700));
    expect(tester.takeException(), isNull);
  });
}
