import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/inbox/email_tile.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('shows category, subject, urgency and trashed badge', (
    tester,
  ) async {
    final email = EmailItem.fromJson({
      ...fixtureMap('email_item'),
      'is_trashed': true,
    });
    await pumpScreen(
      tester,
      Scaffold(body: EmailTile(email: email)),
      overrides: [
        ...await testOverrides(adapter: FakeAdapter({})),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 23)),
      ],
    );
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text(email.subject), findsOneWidget);
    expect(find.text('Trashed'), findsOneWidget);
    expect(find.bySemanticsLabel('Urgency 5 of 5'), findsOneWidget);
  });

  testWidgets('survives 200% text scale without overflow', (tester) async {
    final email = EmailItem.fromJson(fixtureMap('email_item'));
    await pumpScreen(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: ListView(children: [EmailTile(email: email)]),
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(tester.takeException(), isNull);
  });
}
