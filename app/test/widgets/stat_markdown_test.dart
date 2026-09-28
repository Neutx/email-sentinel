import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/widgets/markdown_body.dart';
import 'package:sentinel/widgets/stat_tile.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('StatTile shows value, label, icon and exposes semantics', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: StatTile(
          icon: Icons.task_alt_rounded,
          value: 3,
          label: 'Open actions',
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );

    expect(find.bySemanticsLabel('3 Open actions'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Open actions'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
  });

  testWidgets('MarkdownBody renders headings and paragraph text', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: MarkdownBody(
            data: '## Needs you\n- **Contract renewal** needs a signature today.\n\nParagraph text here.',
          ),
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );

    expect(find.text('Needs you'), findsOneWidget);
    expect(find.textContaining('Contract renewal'), findsOneWidget);
    expect(find.textContaining('Paragraph text here.'), findsOneWidget);
  });
}
