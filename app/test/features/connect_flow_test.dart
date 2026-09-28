import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/app/app.dart';
import 'package:sentinel/core/config/connection_config.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

final _okRoutes = {
  'GET /api/health': const FakeResponse.fixture('health'),
  'GET /api/status': const FakeResponse.fixture('status'),
};

Future<void> pumpApp(
  WidgetTester tester,
  FakeAdapter adapter, {
  ConnectionConfig? connection,
}) async {
  final overrides = await testOverrides(
    adapter: adapter,
    connection: connection,
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: overrides,
      child: const SentinelApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('URL and token validation', () {
    expect(
      ConnectionConfig.normalizeUrl(' my-pc.ts.net:8765/ '),
      'http://my-pc.ts.net:8765',
    );
    expect(ConnectionConfig.validateUrl(''), isNotNull);
    expect(ConnectionConfig.validateUrl('ftp://x'), isNotNull);
    expect(ConnectionConfig.validateUrl('http://100.125.243.21:8765'), isNull);
    expect(ConnectionConfig.validateToken('short'), isNotNull);
    expect(ConnectionConfig.validateToken('a' * 30), isNull);
  });

  testWidgets('unconnected app shows Connect and validates the token', (
    tester,
  ) async {
    await pumpApp(tester, FakeAdapter(_okRoutes));
    expect(find.text('Connect to Sentinel'), findsOneWidget);
    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();
    expect(find.text('Paste the API token.'), findsOneWidget);
  });

  testWidgets('successful connect lands on the four-tab shell', (tester) async {
    await pumpApp(tester, FakeAdapter(_okRoutes));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API token'),
      'a-valid-token-0123456789abcdef',
    );
    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();
    for (final label in ['Briefing', 'Inbox', 'Projects', 'Control']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
  });

  testWidgets('a rejected token shows a specific error', (tester) async {
    await pumpApp(
      tester,
      FakeAdapter({
        'GET /api/health': const FakeResponse.fixture('health'),
        'GET /api/status': const FakeResponse({'detail': 'bad'}, status: 401),
      }),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'API token'),
      'a-wrong-token-0123456789abcdef',
    );
    await tester.tap(find.text('Test & connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rejected the API token'), findsOneWidget);
  });

  testWidgets('a saved connection skips straight to the shell', (tester) async {
    await pumpApp(tester, FakeAdapter(_okRoutes), connection: testConfig);
    expect(find.text('Connect to Sentinel'), findsNothing);
    expect(find.bySemanticsLabel('Inbox'), findsWidgets);
  });
}
