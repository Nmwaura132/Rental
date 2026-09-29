import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/core/providers/user_role_provider.dart';
import 'package:rental_manager/core/widgets/kasa_layout.dart';
import 'package:rental_manager/features/dashboard/needs_attention.dart';
import 'package:rental_manager/features/properties/property_detail_screen.dart';
import 'package:rental_manager/features/properties/unit_numbering.dart';

import 'support/kasa_test_fonts.dart';

class _Offline implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
}

// Deliberately out of order: the screen has to sort them.
Map<String, dynamic> _unit(int id, String number, int floor, String state, String? tenant) => {
      'id': id,
      'unit_number': number,
      'floor': floor,
      'state': state,
      'status': state == 'vacant' ? 'vacant' : 'occupied',
      'tenant_name': tenant,
      'rent_amount': '25000.00',
    };

final _property = <String, dynamic>{
  'id': 1,
  'name': 'Mwangaza Court',
  'town': 'Kilimani',
  'county': 'Nairobi',
  'units': [
    _unit(4, '1B', 1, 'vacant', null),
    _unit(5, 'G10', 0, 'paid', 'Grace Wanjiru'),
    _unit(1, 'G1', 0, 'paid', 'Achieng Otieno'),
    _unit(6, '2A', 2, 'notice', 'Brian Otieno'),
    _unit(2, 'G2', 0, 'arrears', 'Peter Kamau'),
    _unit(3, '1A', 1, 'arrears', 'Mercy Chebet'),
  ],
};

Future<void> _pump(
  WidgetTester tester, {
  String role = 'landlord',
  int missing = 0,
  Size size = const Size(360, 780),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });

  final dio = Dio()..httpClientAdapter = _Offline();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      userRoleProvider.overrideWith((ref) async => role),
      propertyDetailProvider.overrideWith((ref, id) async => _property),
      missingReadingsProvider.overrideWith((ref) async => [
            if (missing > 0)
              MissingReadings(
                  propertyId: 1, propertyName: 'Mwangaza Court', missing: missing, total: 6),
          ]),
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: const PropertyDetailScreen(propertyId: 1),
    ),
  ));
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, String label) => tester.getTopLeft(find.text(label)).dy;
double _x(WidgetTester tester, String label) => tester.getTopLeft(find.text(label)).dx;

void main() {
  setUpAll(loadKasaFonts);

  group('the unit grid', () {
    testWidgets('puts the ground floor first, then up the building', (tester) async {
      await _pump(tester);
      // Three to a row: G1, G2, G10 on the first, 1A, 1B, 2A on the second.
      expect(_y(tester, 'G1'), lessThan(_y(tester, '1A')));
      expect(_x(tester, '1A'), lessThan(_x(tester, '1B')));
      expect(_x(tester, '1B'), lessThan(_x(tester, '2A')));
    });

    testWidgets('sorts numbers the way a person would: G2 before G10', (tester) async {
      await _pump(tester);
      // Three to a row, so G1, G2, G10 share one.
      expect(_x(tester, 'G1'), lessThan(_x(tester, 'G2')));
      expect(_x(tester, 'G2'), lessThan(_x(tester, 'G10')));
    });

    testWidgets('lays three units across', (tester) async {
      await _pump(tester);
      expect(_y(tester, 'G1'), _y(tester, 'G10'));
    });

    testWidgets('names who lives in each unit', (tester) async {
      await _pump(tester);
      expect(find.text('Achieng Otieno'), findsOneWidget);
      expect(find.text('No tenant'), findsOneWidget);
    });

    testWidgets('shows each unit’s status as a word', (tester) async {
      await _pump(tester);
      expect(find.text('Paid'), findsNWidgets(2));
      expect(find.text('Arrears'), findsNWidgets(2));
      expect(find.text('Vacant'), findsOneWidget);
      expect(find.text('Notice'), findsOneWidget);
    });
  });

  group('the filters', () {
    testWidgets('count the units in each state', (tester) async {
      await _pump(tester);
      final pills = tester.widgetList<KasaFilterPill>(find.byType(KasaFilterPill)).toList();
      expect(pills.map((p) => p.count).toList(), [6, 2, 1, 1]);
    });

    testWidgets('Arrears keeps only units in arrears', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.byType(KasaFilterPill).at(1));
      await tester.tap(find.byType(KasaFilterPill).at(1));
      await tester.pumpAndSettle();
      expect(find.text('G2'), findsOneWidget);
      expect(find.text('G1'), findsNothing);
    });

    testWidgets('Vacant keeps only vacant units', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.byType(KasaFilterPill).at(2));
      await tester.tap(find.byType(KasaFilterPill).at(2));
      await tester.pumpAndSettle();
      expect(find.text('1B'), findsOneWidget);
      expect(find.text('G2'), findsNothing);
    });
  });

  group('the header', () {
    testWidgets('says where it is and how full', (tester) async {
      await _pump(tester);
      expect(find.text('Kilimani, Nairobi'), findsOneWidget);
      expect(find.textContaining('5/6', findRichText: true), findsOneWidget);
    });

    testWidgets('says how many meters still need reading', (tester) async {
      await _pump(tester, missing: 2);
      expect(find.text('2 missing'), findsOneWidget);
    });

    testWidgets('has no meter warning when every meter is read', (tester) async {
      await _pump(tester);
      expect(find.textContaining('missing'), findsNothing);
    });
  });

  group('who is offered what', () {
    testWidgets('the landlord can renumber and add a tenant', (tester) async {
      await _pump(tester);
      expect(find.text('Renumber units'), findsOneWidget);
      expect(find.text('Add tenant'), findsOneWidget);
    });

    testWidgets('a caretaker can read meters and add a tenant, but not renumber', (tester) async {
      await _pump(tester, role: 'caretaker');
      expect(find.text('Meter readings'), findsOneWidget);
      expect(find.text('Add tenant'), findsOneWidget);
      expect(find.text('Renumber units'), findsNothing);
    });
  });

  group('small phones and large text', () {
    testWidgets('fit at 360 wide with text 30% larger', (tester) async {
      // A RenderFlex overflow throws, so this fails on any clipped tile.
      await _pump(tester, textScale: 1.3, missing: 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fit at 320 wide with text 30% larger', (tester) async {
      await _pump(tester, size: const Size(320, 640), textScale: 1.3, missing: 4);
      expect(tester.takeException(), isNull);
    });
  });

  group('compareUnitNumbers', () {
    test('reads digit runs as numbers', () {
      expect(compareUnitNumbers('G2', 'G10'), lessThan(0));
    });

    test('puts 1A before 1B', () {
      expect(compareUnitNumbers('1A', '1B'), lessThan(0));
    });

    test('puts 1B before 2A', () {
      expect(compareUnitNumbers('1B', '2A'), lessThan(0));
    });

    test('treats equal numbers as equal', () {
      expect(compareUnitNumbers('G1', 'G1'), 0);
    });
  });
}
