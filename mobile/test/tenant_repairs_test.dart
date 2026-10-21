import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/dashboard/dashboard_screen.dart';
import 'package:rental_manager/features/maintenance/maintenance_screen.dart';
import 'package:rental_manager/features/maintenance/tenant_repairs_screen.dart';

import 'support/kasa_test_fonts.dart';

class _Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return ResponseBody.fromString('{"id": 9}', 201, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

const _home = {'tenancy_id': 3, 'unit_number': 'G1', 'property_name': 'Maria Goretti Apartment'};

const _requests = [
  {
    'id': 1,
    'title': 'Kitchen tap leaking',
    'status': 'open',
    'priority': 'urgent',
    'created_at': '2026-10-18T09:00:00+03:00',
    'resolved_at': null,
  },
  {
    'id': 2,
    'title': 'Bedroom door lock',
    'status': 'resolved',
    'priority': 'low',
    'created_at': '2026-09-02T09:00:00+03:00',
    'resolved_at': '2026-09-05T09:00:00+03:00',
  },
];

Future<_Server> _pump(
  WidgetTester tester,
  Widget child, {
  List<Map<String, dynamic>> requests = _requests,
  Map<String, dynamic> home = _home,
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
  final server = _Server();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server),
      dashboardProvider.overrideWith((ref) async => home),
      maintenanceListProvider.overrideWith((ref) async => requests),
    ],
    child: MaterialApp(theme: ThemeData(colorScheme: const ColorScheme.light()), home: child),
  ));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  setUpAll(loadKasaFonts);

  testWidgets('open requests come first', (tester) async {
    await _pump(tester, const TenantRepairsScreen());
    final open = tester.getTopLeft(find.text('Kitchen tap leaking')).dy;
    final done = tester.getTopLeft(find.text('Bedroom door lock')).dy;
    expect(open < done, isTrue);
  });

  testWidgets('a fixed request says when it was fixed', (tester) async {
    await _pump(tester, const TenantRepairsScreen());
    expect(find.text('Reported 2 Sep · fixed 5 Sep'), findsOneWidget);
  });

  testWidgets('an open request says it is reported', (tester) async {
    await _pump(tester, const TenantRepairsScreen());
    expect(find.text('Reported'), findsOneWidget);
  });

  testWidgets('with nothing reported, it explains what this is for', (tester) async {
    await _pump(tester, const TenantRepairsScreen(), requests: const []);
    expect(find.text('Nothing reported'), findsOneWidget);
  });

  testWidgets('without a home there is nothing to report against', (tester) async {
    await _pump(tester, const TenantRepairsScreen(), home: const {});
    expect(find.text('Report a repair'), findsNothing);
  });

  testWidgets('a report needs to say what is wrong', (tester) async {
    final server = await _pump(tester, const ReportRepairScreen());
    await tester.tap(find.text('Send to landlord'));
    await tester.pumpAndSettle();
    expect(server.requests, isEmpty);
  });

  testWidgets('a report goes to the tenancy, with its urgency', (tester) async {
    final server = await _pump(tester, const ReportRepairScreen());
    await tester.enterText(find.byType(TextFormField).first, 'No water since morning');
    await tester.tap(find.text('Emergency'));
    await tester.pump();
    await tester.tap(find.text('Send to landlord'));
    await tester.pumpAndSettle();
    final sent = Map.fromEntries((server.requests.single.data as FormData).fields);
    expect(sent, {
      'tenancy': '3',
      'title': 'No water since morning',
      'description': '',
      'priority': 'urgent',
    });
  });

  for (final width in [360.0, 320.0]) {
    testWidgets('the list fits at $width wide, text 30% larger', (tester) async {
      await _pump(tester, const TenantRepairsScreen(), size: Size(width, 800), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the report form fits at $width wide, text 30% larger', (tester) async {
      await _pump(tester, const ReportRepairScreen(), size: Size(width, 800), textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }
}
