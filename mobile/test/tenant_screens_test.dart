import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/core/providers/user_role_provider.dart';
import 'package:rental_manager/features/dashboard/dashboard_screen.dart';
import 'package:rental_manager/features/dashboard/tenant_home.dart';
import 'package:rental_manager/features/more/tenant_me_screen.dart';
import 'package:rental_manager/features/payments/invoices_screen.dart';
import 'package:rental_manager/features/payments/tenant_pay_screen.dart';

import 'support/kasa_test_fonts.dart';

class _Offline implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
}

const _owing = <String, dynamic>{
  'unit_number': 'G1',
  'property_name': 'Maria Goretti Apartment',
  'outstanding_balance': '25840.00',
  'open_bills': 1,
  'current_bill': {
    'id': 7,
    'period_start': '2026-10-01',
    'due_date': '2026-10-05',
    'amount_due': '25840.00',
    'amount_paid': '0.00',
    'balance': '25840.00',
    'status': 'pending',
    'lines': [
      {'description': 'Rent', 'charge_type': 'rent', 'amount': '25000.00'},
      {'description': 'Water', 'charge_type': 'water', 'amount': '640.00'},
      {'description': 'Garbage', 'charge_type': 'garbage', 'amount': '200.00'},
    ],
  },
  'mpesa_paybill': '899790',
  'pay_account': '623943#G1',
  'stk_enabled': false,
  'bank_accounts': [],
  'credit': '0',
  'deposit_held': '25000.00',
  'last_paid': {'period_start': '2026-09-01', 'amount': '25840.00', 'paid_at': '2026-09-03T10:00:00+03:00'},
  'monthly_rent': 25000.0,
  'tenancy_start': '2025-03-01',
  'tenancy_id': 3,
  'notice_effective_date': null,
  'notice_by': null,
  'notice_reason': '',
};

Map<String, dynamic> _with(Map<String, dynamic> changes) => {..._owing, ...changes};

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, dynamic> home = _owing,
  List<Map<String, dynamic>> payments = const [],
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
  FlutterSecureStorage.setMockInitialValues({'user_name': 'Achieng Otieno', 'user_phone': '+254712345678'});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()..httpClientAdapter = _Offline()),
      userRoleProvider.overrideWith((ref) async => 'tenant'),
      dashboardProvider.overrideWith((ref) async => home),
      paymentsReceivedProvider.overrideWith((ref) async => payments),
      invoicesProvider.overrideWith((ref) async => <dynamic>[]),
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}

Widget _homeHost(Map<String, dynamic> data) =>
    Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [TenantHome(data: data)]));

void main() {
  setUpAll(loadKasaFonts);

  group('tenant home', () {
    testWidgets('shows what is owed', (tester) async {
      await _pump(tester, _homeHost(_owing));
      expect(find.text('KES 25,840'), findsOneWidget);
    });

    testWidgets('says what the bill is made of', (tester) async {
      await _pump(tester, _homeHost(_owing));
      expect(find.text('Rent 25,000 · Water 640 · Garbage 200'), findsOneWidget);
    });

    testWidgets('says when it is due', (tester) async {
      await _pump(tester, _homeHost(_owing));
      expect(find.text('Due 5 Oct'), findsOneWidget);
    });

    testWidgets('gives the paybill and account to pay to', (tester) async {
      await _pump(tester, _homeHost(_owing));
      expect(find.text('623943#G1'), findsOneWidget);
    });

    testWidgets('copies the account number', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      await _pump(tester, _homeHost(_owing));
      await tester.tap(find.text('Copy').last);
      await tester.pump();
      expect(copied, '623943#G1');
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('a till is shown without an account', (tester) async {
      await _pump(tester, _homeHost(_with({'mpesa_paybill': '123456', 'pay_account': ''})));
      expect(find.text('Till number'), findsOneWidget);
    });

    testWidgets('names the last month paid', (tester) async {
      await _pump(tester, _homeHost(_owing));
      expect(find.text('September paid'), findsOneWidget);
    });

    testWidgets('says plainly when nothing is owed', (tester) async {
      await _pump(tester, _homeHost(_with({'current_bill': null, 'outstanding_balance': '0'})));
      expect(find.text('Nothing to pay'), findsOneWidget);
    });

    testWidgets('totals several open bills, oldest paid first', (tester) async {
      await _pump(tester, _homeHost(_with({'open_bills': 2, 'outstanding_balance': '51680.00'})));
      expect(find.text('Across 2 bills. The oldest is paid first.'), findsOneWidget);
    });

    testWidgets("tells them when the landlord has given notice, and why", (tester) async {
      await _pump(
        tester,
        _homeHost(_with({
          'notice_effective_date': '2026-11-30',
          'notice_by': 'landlord',
          'notice_reason': 'Selling the building',
        })),
      );
      expect(find.textContaining('Selling the building'), findsOneWidget);
    });

    testWidgets('offers no M-Pesa prompt behind a shared paybill', (tester) async {
      await _pump(tester, const DashboardScreen());
      expect(find.textContaining('with M-Pesa'), findsNothing);
    });

    testWidgets('offers the prompt where one can be sent', (tester) async {
      await _pump(tester, const DashboardScreen(), home: _with({'stk_enabled': true}));
      expect(find.text('Pay KES 25,840 with M-Pesa'), findsOneWidget);
    });
  });

  group('pay tab', () {
    const payments = [
      {
        'id': 1,
        'amount': '25840.00',
        'method': 'mpesa',
        'mpesa_receipt_number': 'SIR4K7X2QP',
        'paid_at': '2026-09-03T10:00:00+03:00',
        'period_start': '2026-09-01',
      },
      {
        'id': 2,
        'amount': '25840.00',
        'method': 'cash',
        'paid_at': '2026-06-05T10:00:00+03:00',
        'period_start': '2026-06-01',
      },
    ];

    testWidgets('shows the bill to pay now', (tester) async {
      await _pump(tester, const TenantPayScreen(), payments: payments);
      expect(find.text('October bill · due 5 Oct'), findsOneWidget);
    });

    testWidgets('lists each payment with its M-Pesa code', (tester) async {
      await _pump(tester, const TenantPayScreen(), payments: payments);
      expect(find.text('3 Sep · M-Pesa SIR4K7X2QP'), findsOneWidget);
    });

    testWidgets('says who recorded a cash payment', (tester) async {
      await _pump(tester, const TenantPayScreen(), payments: payments);
      expect(find.text('5 Jun · Cash · recorded by landlord'), findsOneWidget);
    });

    testWidgets('says how much deposit the landlord holds', (tester) async {
      await _pump(tester, const TenantPayScreen(), payments: payments);
      expect(find.text('Deposit held by your landlord: KES 25,000.'), findsOneWidget);
    });
  });

  group('me', () {
    testWidgets('shows who they are', (tester) async {
      await _pump(tester, const TenantMeScreen());
      expect(find.text('Achieng Otieno'), findsOneWidget);
    });

    testWidgets('shows their rent', (tester) async {
      await _pump(tester, const TenantMeScreen());
      expect(find.text('KES 25,000 / month'), findsOneWidget);
    });

    testWidgets('offers notice while none is given', (tester) async {
      await _pump(tester, const TenantMeScreen());
      expect(find.text('Give notice to move out'), findsOneWidget);
    });

    testWidgets('does not offer it twice', (tester) async {
      await _pump(tester, const TenantMeScreen(), home: _with({'notice_effective_date': '2026-11-30'}));
      expect(find.text('Notice given'), findsOneWidget);
    });

    testWidgets('notice says the move-out date before they confirm', (tester) async {
      await _pump(tester, const TenantMeScreen());
      await tester.tap(find.text('Give notice to move out'));
      await tester.pumpAndSettle();
      expect(find.textContaining('You would move out by'), findsOneWidget);
    });
  });

  test('the move-out date is the last day of next month', () {
    expect(vacateBy(DateTime(2026, 9, 10)), DateTime(2026, 10, 31));
  });

  test('even from the end of a year', () {
    expect(vacateBy(DateTime(2026, 12, 31)), DateTime(2027, 1, 31));
  });

  group('small phones and large text', () {
    for (final width in [360.0, 320.0]) {
      testWidgets('home fits at $width wide, text 30% larger', (tester) async {
        await _pump(tester, _homeHost(_with({'notice_effective_date': '2026-11-30', 'notice_by': 'landlord'})),
            size: Size(width, 900), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('pay tab fits at $width wide, text 30% larger', (tester) async {
        await _pump(tester, const TenantPayScreen(), payments: const [
          {'id': 1, 'amount': '125840.00', 'method': 'mpesa', 'mpesa_receipt_number': 'SIR4K7X2QP',
           'paid_at': '2026-09-03T10:00:00+03:00', 'period_start': '2026-09-01'},
        ], size: Size(width, 800), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('me fits at $width wide, text 30% larger', (tester) async {
        await _pump(tester, const TenantMeScreen(), size: Size(width, 800), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('give notice fits at $width wide, text 30% larger', (tester) async {
        await _pump(tester, const GiveNoticeScreen(home: _owing), size: Size(width, 800), textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
