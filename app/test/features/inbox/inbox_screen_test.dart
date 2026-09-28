import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/features/inbox/inbox_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<FakeAdapter> pumpInbox(
    WidgetTester tester,
    Map<String, FakeResponse> routes, {
    bool offline = false,
  }) async {
    final adapter = FakeAdapter(routes, offline: offline);
    await pumpScreen(
      tester,
      const InboxScreen(),
      overrides: [
        ...await testOverrides(adapter: adapter),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 23, 59)),
      ],
    );
    return adapter;
  }

  testWidgets('renders the feed under a day header', (tester) async {
    await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Team lunch on Friday'), findsOneWidget);
  });

  testWidgets('swipe right marks done and Undo restores', (tester) async {
    final adapter = await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse.fixture('email_page'),
      'POST /api/emails/5/done': const FakeResponse.fixture('action_result'),
    });
    await tester.drag(
      find.byKey(const ValueKey('email-5')),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Team lunch on Friday'), findsNothing);
    expect(adapter.requests.last.data, {'done': true});
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.data, {'done': false});
    expect(find.text('Team lunch on Friday'), findsOneWidget);
  });

  testWidgets('filter chip requests only that category', (tester) async {
    final adapter = await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    await tester.tap(find.widgetWithText(ChoiceChip, 'Urgent'));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters['category'], [
      'urgent_actionable',
    ]);
  });

  testWidgets('empty feed shows the All clear state', (tester) async {
    await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse({
        'items': <Object>[],
        'next_cursor': null,
      }),
    });
    expect(find.text('All clear'), findsOneWidget);
  });

  testWidgets('offline shows the Tailscale hint with Retry', (tester) async {
    await pumpInbox(tester, {}, offline: true);
    expect(find.textContaining('Tailscale'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a failed done swipe keeps the tile and explains why', (
    tester,
  ) async {
    await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse.fixture('email_page'),
      'POST /api/emails/5/done': const FakeResponse({
        'detail': 'boom',
      }, status: 500),
    });
    await tester.drag(
      find.byKey(const ValueKey('email-5')),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Team lunch on Friday'), findsOneWidget);
    expect(find.textContaining('Server error'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('pull-to-refresh failure shows a message, not a crash', (
    tester,
  ) async {
    final adapter = await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    adapter.routes.remove('GET /api/emails');
    await tester.fling(
      find.text('Team lunch on Friday'),
      const Offset(0, 600),
      1000,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
