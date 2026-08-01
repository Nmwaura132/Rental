import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/payments/reports_screen.dart';

void main() {
  testWidgets('tenant ledger report sends the selected lease', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, String>? reportQuery;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final path = options.uri.path;
          Object data;
          if (path == '/api/v1/properties/') {
            data = {
              'next': null,
              'results': [
                {'id': 10, 'name': 'Kasa Apartments'},
              ],
            };
          } else if (path == '/api/v1/tenants/leases/') {
            data = {
              'next': null,
              'results': [
                {
                  'id': 55,
                  'tenant_name': 'Test Tenant',
                  'unit_number': 'A1-TEST',
                },
              ],
            };
          } else {
            reportQuery = options.uri.queryParameters;
            data = {'pdf_url': 'https://files.example.test/ledger.pdf'};
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final ledgerCard = find.ancestor(
      of: find.text('Tenant Ledger'),
      matching: find.byType(Card),
    );
    final generateButton = find.descendant(
      of: ledgerCard,
      matching: find.widgetWithText(OutlinedButton, 'Generate PDF'),
    );
    await tester.ensureVisible(generateButton);
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

    expect(reportQuery?['type'], 'ledger');
    expect(reportQuery?['lease'], '55');
    expect(reportQuery?.containsKey('property'), isFalse);
  });
}
