import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/core/providers/user_role_provider.dart';
import 'package:rental_manager/features/properties/properties_screen.dart';

import 'support/kasa_test_fonts.dart';

class _Offline implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
}

const _mwangaza = <String, dynamic>{
  'id': 1,
  'name': 'Mwangaza Court',
  'town': 'Kilimani',
  'county': 'Nairobi',
  'summary': {
    'units': 6,
    'occupied': 5,
    'vacant': 1,
    'notice': 1,
    'overdue_bills': 2,
    'expected_this_month': '100000.00',
    'collected_this_month': '74000.00',
    'collected_pct': 74,
    'arrears': '32440.00',
  },
};

const _baraka = <String, dynamic>{
  'id': 2,
  'name': 'Baraka Flats',
  'town': 'Ruaka',
  'county': 'Kiambu',
  'summary': {
    'units': 4,
    'occupied': 4,
    'vacant': 0,
    'notice': 0,
    'overdue_bills': 1,
    'expected_this_month': '80000.00',
    'collected_this_month': '76800.00',
    'collected_pct': 96,
    'arrears': '5160.00',
  },
};

// What a caretaker's server sends: no money, no overdue count.
const _mwangazaForCaretaker = <String, dynamic>{
  'id': 1,
  'name': 'Mwangaza Court',
  'town': 'Kilimani',
  'county': 'Nairobi',
  'summary': {'units': 6, 'occupied': 5, 'vacant': 1, 'notice': 1},
};

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> properties,
  String role = 'landlord',
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

  final dio = Dio()..httpClientAdapter = _Offline();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      userRoleProvider.overrideWith((ref) async => role),
      propertiesProvider.overrideWith((ref) async => properties),
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: const PropertiesScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKasaFonts);

  group('the landlord’s list', () {
    testWidgets('totals the portfolio in one line', (tester) async {
      await _pump(tester, properties: [_mwangaza, _baraka]);
      expect(find.text('2 properties · 10 units · 9 occupied'), findsOneWidget);
    });

    testWidgets('names each building and where it is', (tester) async {
      await _pump(tester, properties: [_mwangaza, _baraka]);
      expect(find.text('Mwangaza Court'), findsOneWidget);
      expect(find.text('Kilimani, Nairobi · 6 units'), findsOneWidget);
    });

    testWidgets('shows how full, how much is in, and what is owed', (tester) async {
      await _pump(tester, properties: [_mwangaza]);
      expect(find.text('5/6'), findsOneWidget);
      expect(find.text('74%'), findsOneWidget);
      expect(find.text('KES 32,440'), findsOneWidget);
    });

    testWidgets('flags what needs attention, as words', (tester) async {
      await _pump(tester, properties: [_mwangaza]);
      expect(find.text('2 overdue'), findsOneWidget);
      expect(find.text('1 notice'), findsOneWidget);
      expect(find.text('1 vacant'), findsOneWidget);
    });

    testWidgets('says nothing of a building with nothing wrong', (tester) async {
      await _pump(tester, properties: [
        {
          ..._baraka,
          'summary': {..._baraka['summary'] as Map<String, dynamic>, 'overdue_bills': 0, 'arrears': '0.00'},
        },
      ]);
      expect(find.textContaining('overdue'), findsNothing);
      expect(find.textContaining('vacant'), findsNothing);
    });

    testWidgets('does not show 0% when nothing has been billed yet', (tester) async {
      await _pump(tester, properties: [
        {
          ..._baraka,
          'summary': {..._baraka['summary'] as Map<String, dynamic>, 'collected_pct': null},
        },
      ]);
      expect(find.text('0%'), findsNothing);
      expect(find.text('–'), findsOneWidget);
    });

    testWidgets('offers Add property', (tester) async {
      await _pump(tester, properties: [_mwangaza]);
      expect(find.text('Add property'), findsOneWidget);
    });

    testWidgets('invites the first property when there are none', (tester) async {
      await _pump(tester, properties: []);
      expect(find.text('No properties yet.'), findsOneWidget);
    });
  });

  group('the caretaker’s list', () {
    testWidgets('is titled Units and has no way to add a property', (tester) async {
      await _pump(tester, properties: [_mwangazaForCaretaker], role: 'caretaker');
      expect(find.text('Units'), findsOneWidget);
      expect(find.text('Add property'), findsNothing);
    });

    testWidgets('shows who is where but no money', (tester) async {
      await _pump(tester, properties: [_mwangazaForCaretaker], role: 'caretaker');
      expect(find.text('5/6'), findsOneWidget);
      expect(find.text('Collected'), findsNothing);
      expect(find.text('Arrears'), findsNothing);
      expect(find.textContaining('KES'), findsNothing);
    });

    testWidgets('still says who is leaving and what is vacant', (tester) async {
      await _pump(tester, properties: [_mwangazaForCaretaker], role: 'caretaker');
      expect(find.text('1 notice'), findsOneWidget);
      expect(find.text('1 vacant'), findsOneWidget);
    });

    testWidgets('never shows an overdue flag, even if the server sent a count', (tester) async {
      // Belt and braces: the server withholds it, and the screen must not
      // reintroduce it if an older server sends one.
      await _pump(tester, role: 'caretaker', properties: [
        {
          ..._mwangazaForCaretaker,
          'summary': {..._mwangazaForCaretaker['summary'] as Map<String, dynamic>, 'overdue_bills': 3},
        },
      ]);
      expect(find.textContaining('overdue'), findsNothing);
    });
  });

  group('small phones and large text', () {
    for (final role in ['landlord', 'caretaker']) {
      testWidgets('$role: fits at 360 wide with text 30% larger', (tester) async {
        await _pump(
          tester,
          role: role,
          size: const Size(360, 780),
          textScale: 1.3,
          properties: [role == 'landlord' ? _mwangaza : _mwangazaForCaretaker, _baraka],
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('$role: fits at 320 wide with text 30% larger', (tester) async {
        await _pump(
          tester,
          role: role,
          size: const Size(320, 640),
          textScale: 1.3,
          properties: [role == 'landlord' ? _mwangaza : _mwangazaForCaretaker, _baraka],
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
