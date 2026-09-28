import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/widgets/category_chip.dart';
import 'package:sentinel/widgets/urgency_pips.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('chip shows icon and label for every category', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Wrap(
          children: [
            for (final c in EmailCategory.values) CategoryChip(category: c),
          ],
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    for (final c in EmailCategory.values) {
      expect(find.text(c.label), findsOneWidget);
    }
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
  });

  testWidgets('urgency pips expose a semantic label', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(body: UrgencyPips(urgency: 4)),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.bySemanticsLabel('Urgency 4 of 5'), findsOneWidget);
  });
}
