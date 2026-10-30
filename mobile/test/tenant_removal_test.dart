import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/core/api/api_client.dart';
import 'package:rental_manager/features/tenants/tenant_removal.dart';

import 'support/kasa_test_fonts.dart';

class _Server implements HttpClientAdapter {
  _Server(this.preview);
  final Map<String, dynamic> preview;
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return o.method == 'DELETE'
        ? ResponseBody.fromString('', 204)
        : ResponseBody.fromString(jsonEncode(preview), 200, headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
  }
}

const _deletable = {
  'name': 'Elasmus Kiprop', 'houses': ['G1'], 'bills': 2, 'payments': 1, 'paid': '25000.00',
  'can_delete': true, 'reason': '',
};

const _blocked = {
  'name': 'Elasmus Kiprop', 'houses': ['G1'], 'bills': 2, 'payments': 1, 'paid': '25000.00',
  'can_delete': false,
  'reason': 'This tenant has M-Pesa or bank payments on record, which cannot be deleted. '
      'Give notice to end their tenancy instead.',
};

Future<_Server> _open(WidgetTester tester, Map<String, dynamic> preview, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final server = _Server(preview);
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'http://t'))..httpClientAdapter = server)],
    child: MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light()),
      home: Consumer(builder: (context, ref, _) => Scaffold(
        body: TextButton(onPressed: () => deleteTenant(context, ref, 12), child: const Text('open')),
      )),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  setUpAll(loadKasaFonts);

  testWidgets('says who is being deleted', (tester) async {
    await _open(tester, _deletable);
    expect(find.text('Delete Elasmus Kiprop?'), findsOneWidget);
  });

  testWidgets('says what payments go with them', (tester) async {
    await _open(tester, _deletable);
    expect(find.text('1 · KES 25,000'), findsOneWidget);
  });

  testWidgets('deletes nothing until confirmed', (tester) async {
    final server = await _open(tester, _deletable);
    expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  testWidgets('keeping them deletes nothing', (tester) async {
    final server = await _open(tester, _deletable);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
  });

  testWidgets('confirming deletes that tenant', (tester) async {
    final server = await _open(tester, _deletable);
    await tester.tap(find.text('Delete tenant'));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method == 'DELETE').single.path, '/api/v1/auth/tenants/12/');
  });

  testWidgets('a tenant with M-Pesa payments explains why not', (tester) async {
    await _open(tester, _blocked);
    expect(find.textContaining('cannot be deleted'), findsOneWidget);
  });

  testWidgets('and offers no delete', (tester) async {
    await _open(tester, _blocked);
    expect(find.text('Delete tenant'), findsNothing);
  });

  testWidgets('fits at 320 wide', (tester) async {
    await _open(tester, _deletable, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
