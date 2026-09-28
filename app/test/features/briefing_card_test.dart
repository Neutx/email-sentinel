import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/briefing/briefing_card.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('a long briefing collapses without painting outside the card', (
    tester,
  ) async {
    final longBody = [
      '## Needs you',
      for (var i = 0; i < 30; i++)
        '- **Item $i** - review something important (sender, urgency 5/5)',
    ].join('\n');
    final briefing = Briefing.fromJson({
      ...fixtureMap('briefing'),
      'body_markdown': longBody,
    });
    await pumpScreen(
      tester,
      Scaffold(
        body: ListView(
          children: [
            BriefingCard(briefing: briefing),
            const Text('Below the card'),
          ],
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );

    expect(tester.takeException(), isNull);
    final collapsed = tester.getSize(find.byType(BriefingCard)).height;
    expect(collapsed, lessThan(520));
    expect(
      tester.getTopLeft(find.text('Below the card')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(BriefingCard)).dy),
    );

    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(BriefingCard)).height,
      greaterThan(collapsed),
    );
    expect(find.text('Show less'), findsOneWidget);
  });
}
