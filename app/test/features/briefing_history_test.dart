import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/features/briefing/briefing_history_screen.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('renders past briefings and expands on tap', (tester) async {
    final adapter = FakeAdapter({
      'GET /api/briefings': const FakeResponse.fixture('briefings'),
    });
    await pumpScreen(
      tester,
      const BriefingHistoryScreen(),
      overrides: [
        ...await testOverrides(adapter: adapter),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 20, 0)),
      ],
    );

    expect(find.text('Past briefings'), findsOneWidget);
    expect(find.text('Morning briefing'), findsOneWidget);
    expect(find.text('Morning'), findsOneWidget);

    // Tap to expand
    await tester.tap(find.text('Morning briefing'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Contract renewal'), findsOneWidget);
  });

  testWidgets('empty briefings list shows empty state', (tester) async {
    final adapter = FakeAdapter({
      'GET /api/briefings': const FakeResponse(<Object>[]),
    });
    await pumpScreen(
      tester,
      const BriefingHistoryScreen(),
      overrides: await testOverrides(adapter: adapter),
    );

    expect(find.text('No past briefings'), findsOneWidget);
  });
}
