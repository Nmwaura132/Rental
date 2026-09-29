import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/core/providers/user_role_provider.dart';
import 'package:rental_manager/features/properties/unit_detail_screen.dart';

import 'support/kasa_test_fonts.dart';

class _Offline implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
}

const _unit = <String, dynamic>{
  'id': 7,
  'unit_number': 'G2',
  'property': 1,
  'rent_amount': '25000.00',
  'deposit_amount': '25000.00',
  'status': 'occupied',
};

/// What the server sends. A caretaker's copy has no money in it, so the
/// [owner] flag drops exactly what the server drops.
Map<String, dynamic> _occupied({
  bool owner = true,
  String? leavingOn,
  double balance = 6600,
}) =>
    {
      'unit': _unit,
      'property_name': 'Mwangaza Court',
      'paybill': '899790',
      'pay_account': '623943#G2',
      'tenancy': {
        'id': 3,
        'start_date': '2025-03-01',
        'rent_amount': '25000.00',
        'status': 'active',
        'notice_given_at': leavingOn == null ? null : '2026-09-28T10:00:00+03:00',
        'notice_effective_date': leavingOn,
        if (owner) ...{
          'deposit_amount': '25000.00',
          'deposit_paid': true,
          'balance': balance.toStringAsFixed(2),
          'overdue': balance > 0,
        },
      },
      'tenant': {
        'id': 9,
        'name': 'Peter Kamau',
        'phone_number': '+254722418903',
        'occupation': 'Teacher',
        'next_of_kin_name': 'Jane Kamau',
        'next_of_kin_phone': '+254700111222',
        if (owner) ...{'kra_pin': '', 'national_id': '12345678'},
      },
      'payments': owner
          ? [
              {
                'id': 1,
                'amount': '19240.00',
                'method': 'mpesa',
                'method_display': 'M-Pesa',
                'paid_at': '2026-08-12T09:00:00+03:00',
                'period_start': '2026-08-01',
                'reference': 'SIC9M2LQ4T',
                'invoice_number': 'INV-202608-AAAAAA',
              },
            ]
          : [],
      'maintenance': [
        {
          'id': 1,
          'title': 'Kitchen tap leaking',
          'status': 'resolved',
          'created_at': '2026-08-09T08:00:00+03:00',
          'resolved_at': '2026-08-12T08:00:00+03:00',
        },
        {
          'id': 2,
          'title': 'Blocked sink',
          'status': 'open',
          'created_at': '2026-09-26T08:00:00+03:00',
          'resolved_at': null,
        },
      ],
    };

final _vacant = <String, dynamic>{
  'unit': {..._unit, 'status': 'vacant'},
  'property_name': 'Mwangaza Court',
  'paybill': '899790',
  'pay_account': '623943#G2',
  'tenancy': null,
  'tenant': null,
  'payments': [],
  'maintenance': [],
};

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> data, {
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
      unitOccupancyProvider.overrideWith((ref, id) async => data),
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: const UnitDetailScreen(unitId: 7),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKasaFonts);

  group('an occupied unit, for the landlord', () {
    testWidgets('names the unit and its property', (tester) async {
      await _pump(tester, _occupied());
      expect(find.textContaining('Unit G2', findRichText: true), findsOneWidget);
      expect(find.textContaining('Mwangaza Court', findRichText: true), findsOneWidget);
    });

    testWidgets('shows who lives there and lets you call them', (tester) async {
      await _pump(tester, _occupied());
      expect(find.text('Peter Kamau'), findsOneWidget);
      expect(find.text('+254722418903'), findsOneWidget);
      expect(find.byTooltip('Call Peter Kamau'), findsOneWidget);
    });

    testWidgets('shows rent, deposit held and what is owed', (tester) async {
      await _pump(tester, _occupied());
      expect(find.text('KES 25,000 / month'), findsWidgets);
      expect(find.text('Deposit held'), findsOneWidget);
      expect(find.text('KES 6,600'), findsOneWidget);
    });

    testWidgets('says overdue in words', (tester) async {
      await _pump(tester, _occupied());
      expect(find.text('Overdue'), findsOneWidget);
    });

    testWidgets('says paid when nothing is owed', (tester) async {
      await _pump(tester, _occupied(balance: 0));
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('lists what was paid, and how', (tester) async {
      await _pump(tester, _occupied());
      expect(find.text('August'), findsOneWidget);
      expect(find.text('M-Pesa · SIC9M2LQ4T'), findsOneWidget);
      expect(find.text('All bills'), findsOneWidget);
    });

    testWidgets('lists repairs with when they were reported and fixed', (tester) async {
      await _pump(tester, _occupied());
      expect(find.text('Kitchen tap leaking'), findsOneWidget);
      expect(find.text('Reported 9 Aug · fixed 12 Aug'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('warns when the tenant has no KRA PIN on file', (tester) async {
      await _pump(tester, _occupied());
      expect(find.text('KRA PIN'), findsOneWidget);
      expect(find.text('Not on file'), findsOneWidget);
    });

    testWidgets('shows where the tenant pays', (tester) async {
      await _pump(tester, _occupied());
      // At the foot of the screen, so it is built only once scrolled to.
      await tester.scrollUntilVisible(find.text('899790'), 300);
      expect(find.text('899790'), findsOneWidget);
      expect(find.text('623943#G2'), findsOneWidget);
    });

    testWidgets('offers Record payment while something is owed', (tester) async {
      await _pump(tester, _occupied());
      expect(find.text('Record payment'), findsOneWidget);
    });

    testWidgets('does not offer it when nothing is owed', (tester) async {
      await _pump(tester, _occupied(balance: 0));
      expect(find.text('Record payment'), findsNothing);
    });
  });

  group('notice', () {
    testWidgets('says when the tenant is leaving', (tester) async {
      await _pump(tester, _occupied(leavingOn: '2099-10-31'));
      expect(find.text('Moving out 31 Oct 2099'), findsOneWidget);
    });

    testWidgets('reminds the landlord about the deposit', (tester) async {
      await _pump(tester, _occupied(leavingOn: '2099-10-31'));
      expect(find.textContaining('before refunding the deposit'), findsOneWidget);
    });

    testWidgets('offers Give notice only while none has been given', (tester) async {
      await _pump(tester, _occupied());
      await tester.tap(find.byTooltip('Unit options'));
      await tester.pumpAndSettle();
      expect(find.text('Give notice'), findsOneWidget);
    });

    testWidgets('does not offer it again once given', (tester) async {
      await _pump(tester, _occupied(leavingOn: '2099-10-31'));
      await tester.tap(find.byTooltip('Unit options'));
      await tester.pumpAndSettle();
      expect(find.text('Give notice'), findsNothing);
    });

    testWidgets('holds back Settle deposit until the last day has come', (tester) async {
      await _pump(tester, _occupied(leavingOn: '2099-10-31'));
      await tester.tap(find.byTooltip('Unit options'));
      await tester.pumpAndSettle();
      expect(find.text('Settle deposit'), findsNothing);
    });

    testWidgets('offers Settle deposit once it has', (tester) async {
      await _pump(tester, _occupied(leavingOn: '2020-01-31'));
      await tester.tap(find.byTooltip('Unit options'));
      await tester.pumpAndSettle();
      expect(find.text('Settle deposit'), findsOneWidget);
    });
  });

  group('an occupied unit, for a caretaker', () {
    testWidgets('shows who lives there and lets you call them', (tester) async {
      await _pump(tester, _occupied(owner: false), role: 'caretaker');
      expect(find.text('Peter Kamau'), findsOneWidget);
      expect(find.byTooltip('Call Peter Kamau'), findsOneWidget);
    });

    testWidgets('shows the repairs to see to', (tester) async {
      await _pump(tester, _occupied(owner: false), role: 'caretaker');
      expect(find.text('Blocked sink'), findsOneWidget);
    });

    testWidgets('shows no deposit, balance or payments', (tester) async {
      await _pump(tester, _occupied(owner: false), role: 'caretaker');
      expect(find.text('Deposit held'), findsNothing);
      expect(find.text('Balance'), findsNothing);
      expect(find.text('Payments'), findsNothing);
    });

    testWidgets('shows no filing details', (tester) async {
      await _pump(tester, _occupied(owner: false), role: 'caretaker');
      expect(find.text('KRA PIN'), findsNothing);
      expect(find.text('ID'), findsNothing);
    });

    testWidgets('has no action to take on money', (tester) async {
      await _pump(tester, _occupied(owner: false), role: 'caretaker');
      expect(find.text('Record payment'), findsNothing);
    });

    testWidgets('has no menu of landlord actions', (tester) async {
      await _pump(tester, _occupied(owner: false), role: 'caretaker');
      expect(find.byTooltip('Unit options'), findsNothing);
    });

    testWidgets('is told about a move-out without the deposit', (tester) async {
      await _pump(tester, _occupied(owner: false, leavingOn: '2099-10-31'), role: 'caretaker');
      expect(find.textContaining('Book the move-out inspection.'), findsOneWidget);
      expect(find.textContaining('deposit'), findsNothing);
    });
  });

  group('a vacant unit', () {
    testWidgets('says so and offers to add a tenant', (tester) async {
      await _pump(tester, _vacant);
      expect(find.text('This unit is vacant.'), findsOneWidget);
      expect(find.text('Add tenant'), findsOneWidget);
    });

    testWidgets('shows the landlord its deposit', (tester) async {
      await _pump(tester, _vacant);
      expect(find.text('Deposit'), findsOneWidget);
    });

    testWidgets('does not show a caretaker the deposit, but still lets them add a tenant', (tester) async {
      await _pump(tester, _vacant, role: 'caretaker');
      expect(find.text('Deposit'), findsNothing);
      expect(find.text('Add tenant'), findsOneWidget);
    });

    testWidgets('lets the landlord delete it', (tester) async {
      await _pump(tester, _vacant);
      await tester.tap(find.byTooltip('Unit options'));
      await tester.pumpAndSettle();
      expect(find.text('Delete unit'), findsOneWidget);
    });

    testWidgets('does not offer to delete an occupied one', (tester) async {
      await _pump(tester, _occupied());
      await tester.tap(find.byTooltip('Unit options'));
      await tester.pumpAndSettle();
      expect(find.text('Delete unit'), findsNothing);
    });
  });

  group('small phones and large text', () {
    for (final (label, data, role) in [
      ('landlord, occupied, leaving', _occupied(leavingOn: '2099-10-31'), 'landlord'),
      ('caretaker, occupied', _occupied(owner: false), 'caretaker'),
      ('landlord, vacant', _vacant, 'landlord'),
    ]) {
      testWidgets('$label: fits at 360 wide with text 30% larger', (tester) async {
        await _pump(tester, data, role: role, size: const Size(360, 780), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label: fits at 320 wide with text 30% larger', (tester) async {
        await _pump(tester, data, role: role, size: const Size(320, 640), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
