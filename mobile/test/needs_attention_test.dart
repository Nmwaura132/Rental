import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/features/dashboard/needs_attention.dart';
import 'package:rental_manager/features/payments/unplaced_payments.dart';
import 'package:rental_manager/features/tenants/tenants_screen.dart';

Map<String, dynamic> _tenancy(String unit, String? out, {String status = 'active'}) => {
      'status': status,
      'unit_number': unit,
      'property_name': 'Mwangaza Court',
      'notice_effective_date': out,
    };

void main() {
  group('buildAttentionItems', () {
    test('nothing waiting gives no rows', () {
      expect(buildAttentionItems(canSeeMoney: true), isEmpty);
    });

    test('orders by urgency: overdue, unassigned, notice, readings', () {
      final items = buildAttentionItems(
        canSeeMoney: true,
        overdueCount: 3,
        overdueAmount: 37600,
        unplaced: [
          {'amount': '12000'}
        ],
        tenancies: [_tenancy('2B', '2026-10-31')],
        missingReadings: const [
          MissingReadings(
              propertyId: 1, propertyName: 'Mwangaza Court', missing: 2, total: 6),
        ],
      );
      expect(items.map((e) => e.kind), [
        AttentionKind.overdue,
        AttentionKind.unassigned,
        AttentionKind.notice,
        AttentionKind.readings,
      ]);
      expect(items[0].title, '3 bills overdue');
      expect(items[0].subtitle, contains('37,600'));
      expect(items[1].title, '1 payment to assign');
      expect(items[1].subtitle, contains('12,000'));
      expect(items[2].subtitle, '2B, Mwangaza Court · leaves 31 Oct');
      expect(items[3].subtitle, 'Mwangaza Court · 4 of 6 units');
    });

    test('singular and plural wording', () {
      final one = buildAttentionItems(
          canSeeMoney: true, overdueCount: 1, overdueAmount: 100);
      expect(one.single.title, '1 bill overdue');
      final many = buildAttentionItems(canSeeMoney: true, unplaced: [
        {'amount': 1},
        {'amount': 2},
      ]);
      expect(many.single.title, '2 payments to assign');
    });

    test('several notices collapse to one row naming the soonest', () {
      final items = buildAttentionItems(canSeeMoney: true, tenancies: [
        _tenancy('4A', '2026-11-30'),
        _tenancy('2B', '2026-10-31'),
        _tenancy('1C', null),
        _tenancy('9Z', '2026-09-30', status: 'ended'),
      ]);
      expect(items.single.title, '2 notices to vacate');
      expect(items.single.subtitle, startsWith('Next: 2B'));
    });

    test('caretakers never see money rows', () {
      final items = buildAttentionItems(
        canSeeMoney: false,
        overdueCount: 3,
        overdueAmount: 1,
        unplaced: [
          {'amount': 5}
        ],
        missingReadings: const [
          MissingReadings(propertyId: 1, propertyName: 'A', missing: 1, total: 2),
        ],
      );
      expect(items.map((e) => e.kind), [AttentionKind.readings]);
    });

    test('a property with every reading in is skipped', () {
      final items = buildAttentionItems(
        canSeeMoney: true,
        missingReadings: const [
          MissingReadings(propertyId: 1, propertyName: 'A', missing: 0, total: 4),
        ],
      );
      expect(items, isEmpty);
    });
  });

  group('missingFromSheet', () {
    Map<String, dynamic> row(int unit, bool occ, num? reading, [int charge = 1]) => {
          'unit': unit,
          'occupied': occ,
          'charge': charge,
          'reading': reading,
        };

    test('counts occupied units without a reading, once per unit', () {
      final m = missingFromSheet(7, 'A', {
        'rows': [
          row(1, true, 10),
          row(2, true, null),
          row(2, true, null, 2), // second meter on the same unit
          row(3, false, null), // vacant: not expected
        ],
      })!;
      expect(m.missing, 1);
      expect(m.total, 2);
    });

    test('returns null when nothing is missing', () {
      expect(
        missingFromSheet(7, 'A', {
          'rows': [row(1, true, 10)]
        }),
        isNull,
      );
      expect(missingFromSheet(7, 'A', {'rows': []}), isNull);
    });
  });

  group('NeedsAttentionSection', () {
    Widget host({
      bool money = true,
      List<Map<String, dynamic>> unplaced = const [],
      List<dynamic> tenancies = const [],
      List<MissingReadings> readings = const [],
      int overdue = 0,
      bool failTenancies = false,
    }) {
      return ProviderScope(
        overrides: [
          unplacedPaymentsProvider.overrideWith((ref) async => unplaced),
          tenanciesProvider.overrideWith((ref) async {
            if (failTenancies) throw Exception('offline');
            return tenancies;
          }),
          missingReadingsProvider.overrideWith((ref) async => readings),
        ],
        child: MaterialApp(
          theme: ThemeData(colorScheme: const ColorScheme.light()),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NeedsAttentionSection(
                canSeeMoney: money,
                overdueCount: overdue,
                overdueAmount: 1000,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows a calm row when nothing is waiting', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('All caught up'), findsOneWidget);
    });

    testWidgets('lists rows with a count', (tester) async {
      await tester.pumpWidget(host(
        overdue: 2,
        unplaced: [
          {'amount': 500}
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('2 bills overdue'), findsOneWidget);
      expect(find.text('1 payment to assign'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // header count
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing source is reported, not hidden', (tester) async {
      await tester.pumpWidget(host(failTenancies: true));
      await tester.pumpAndSettle();
      expect(find.text('Could not check everything'), findsOneWidget);
      expect(find.text('All caught up'), findsNothing);
    });

    testWidgets('a failing source next to real rows still warns', (tester) async {
      await tester.pumpWidget(host(overdue: 1, failTenancies: true));
      await tester.pumpAndSettle();
      expect(find.text('1 bill overdue'), findsOneWidget);
      expect(find.textContaining('could not load'), findsOneWidget);
    });

    testWidgets('lays out at 360dp', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        overdue: 3,
        unplaced: [
          {'amount': 12000}
        ],
        tenancies: [_tenancy('2B', '2026-10-31')],
        readings: const [
          MissingReadings(
              propertyId: 1,
              propertyName: 'A long property name that has to wrap somewhere',
              missing: 2,
              total: 6),
        ],
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
