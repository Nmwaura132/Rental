import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/dashboard/needs_attention.dart';
import 'package:rental_manager/features/properties/meter_readings_screen.dart';
import 'package:rental_manager/features/properties/properties_screen.dart';
import 'package:rental_manager/features/properties/readings_tab_screen.dart';

class _Offline implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
}

Widget _host(List<dynamic> props, {List<MissingReadings> missing = const []}) {
  final dio = Dio()..httpClientAdapter = _Offline();
  return ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      propertiesProvider.overrideWith((ref) async => props),
      missingReadingsProvider.overrideWith((ref) async => missing),
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: const ReadingsTabScreen(),
    ),
  );
}

void main() {
  testWidgets('no properties: says so', (tester) async {
    await tester.pumpWidget(_host([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('do not look after any properties'), findsOneWidget);
  });

  testWidgets('one property opens straight onto its sheet', (tester) async {
    await tester.pumpWidget(_host([
      {'id': 1, 'name': 'Mwangaza Court'}
    ]));
    await tester.pumpAndSettle();
    expect(find.byType(MeterReadingsScreen), findsOneWidget);
  });

  testWidgets('several properties list what is unread', (tester) async {
    await tester.pumpWidget(_host(
      [
        {'id': 1, 'name': 'Mwangaza Court'},
        {'id': 2, 'name': 'Baraka Flats'},
      ],
      missing: const [
        MissingReadings(propertyId: 1, propertyName: 'Mwangaza Court', missing: 2, total: 6),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mwangaza Court'), findsOneWidget);
    expect(find.text('2 of 6 units to read'), findsOneWidget);
    expect(find.text('All read'), findsOneWidget);
    expect(find.byType(MeterReadingsScreen), findsNothing);
  });
}
