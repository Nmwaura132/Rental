import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/core/providers/user_role_provider.dart';
import 'package:rental_manager/features/payments/invoices_screen.dart';
import 'package:rental_manager/features/payments/unplaced_payments.dart';

import 'support/kasa_test_fonts.dart';

class _Offline implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
}

const _overdue = <String, dynamic>{
  'id': 1,
  'invoice_number': 'INV-202608-AAAAAA',
  'tenant_name': 'Peter Kamau',
  'unit_number': 'G2',
  'status': 'overdue',
  'amount_due': '25840.00',
  'amount_paid': '19240.00',
  'balance': '6600.00',
  'due_date': '2026-08-05',
  'period_start': '2026-08-01',
  'period_end': '2026-08-31',
  'notes': '',
  'line_items': [
    {'description': 'Rent — August 2026', 'charge_type': 'rent', 'amount': '25000.00'},
    {
      'description': 'Water — July',
      'charge_type': 'water',
      'previous_reading': '100.00',
      'current_reading': '116.00',
      'units_consumed': '16.00',
      'unit_price': '40.00',
      'amount': '640.00',
    },
    {'description': 'Garbage', 'charge_type': 'garbage', 'amount': '200.00'},
  ],
  'payments': [
    {
      'id': 9,
      'amount': '19240.00',
      'method': 'mpesa',
      'method_display': 'M-Pesa',
      'mpesa_receipt_number': 'SIC9M2LQ4T',
      'paid_at': '2026-08-12T09:00:00+03:00',
      'etims_receipt_number': null,
    },
  ],
};

const _paid = <String, dynamic>{
  'id': 2,
  'invoice_number': 'INV-202609-BBBBBB',
  'tenant_name': 'Achieng Otieno',
  'unit_number': 'G1',
  'status': 'paid',
  'amount_due': '25000.00',
  'amount_paid': '25000.00',
  'balance': '0.00',
  'due_date': '2026-09-05',
  'period_start': '2026-09-01',
  'period_end': '2026-09-30',
  'notes': '',
  'line_items': [],
  'payments': [],
};

Widget _host({String role = 'landlord'}) {
  final dio = Dio()..httpClientAdapter = _Offline();
  return ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      userRoleProvider.overrideWith((ref) async => role),
      invoicesProvider.overrideWith((ref) async => [_overdue, _paid]),
      unplacedPaymentsProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
    ],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: const InvoicesScreen(),
    ),
  );
}

Future<void> _open(WidgetTester tester, String tenant) async {
  await tester.tap(find.text(tenant));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadKasaFonts);

  testWidgets('Money lists what is owed, most urgent first', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final overdue = tester.getTopLeft(find.text('Peter Kamau')).dy;
    final paid = tester.getTopLeft(find.text('Achieng Otieno')).dy;
    expect(overdue, lessThan(paid));
  });

  testWidgets('Money totals what is outstanding', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('6,600 outstanding'), findsOneWidget);
  });

  testWidgets('a bill opens as a full screen titled by its month', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _open(tester, 'Peter Kamau');

    expect(find.text('August bill'), findsOneWidget);
  });

  testWidgets('the bill itemises rent, water and garbage', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _open(tester, 'Peter Kamau');

    expect(find.textContaining('Rent'), findsWidgets);
    expect(find.textContaining('Water'), findsWidgets);
    expect(find.text('Garbage'), findsOneWidget);
  });

  testWidgets('water shows the readings it was worked out from', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _open(tester, 'Peter Kamau');

    expect(find.textContaining('116 − 100 = 16 units'), findsOneWidget);
  });

  testWidgets('the landlord can record a payment and send a reminder', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _open(tester, 'Peter Kamau');

    expect(find.text('Record payment'), findsOneWidget);
    expect(find.byTooltip('Send reminder SMS'), findsOneWidget);
  });

  testWidgets('the landlord can add the eTIMS receipt to a payment', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _open(tester, 'Peter Kamau');

    expect(find.text('+ Add eTIMS receipt'), findsOneWidget);
  });

  testWidgets('a paid bill has no action to take', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _open(tester, 'Achieng Otieno');

    expect(find.text('Record payment'), findsNothing);
  });

  testWidgets('a tenant pays with M-Pesa and sees no landlord tools', (tester) async {
    await tester.pumpWidget(_host(role: 'tenant'));
    await tester.pumpAndSettle();
    await _open(tester, 'Peter Kamau');

    expect(find.textContaining('with M-Pesa'), findsOneWidget);
    expect(find.byTooltip('Send reminder SMS'), findsNothing);
    expect(find.text('+ Add eTIMS receipt'), findsNothing);
  });

  testWidgets('a tenant is not offered the landlord’s shortcuts', (tester) async {
    await tester.pumpWidget(_host(role: 'tenant'));
    await tester.pumpAndSettle();

    expect(find.text('Tax statement'), findsNothing);
    expect(find.text('Record payment'), findsNothing);
  });
}
