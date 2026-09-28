import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/inbox/email_detail_sheet.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('trashed email offers restore and calls the API', (tester) async {
    final email = EmailItem.fromJson({
      ...fixtureMap('email_item'),
      'is_trashed': true,
    });
    final adapter = FakeAdapter({
      'POST /api/emails/1/restore': FakeResponse({
        'ok': true,
        'message': 'Restored to inbox',
        'email': {...fixtureMap('email_item'), 'is_trashed': false},
      }),
    });
    EmailItem? changed;
    await pumpScreen(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: EmailDetailView(email: email, onChanged: (e) => changed = e),
        ),
      ),
      overrides: await testOverrides(adapter: adapter),
    );
    expect(find.text('Protect sender'), findsOneWidget);
    await tester.tap(find.text('Restore from Trash'));
    await tester.pumpAndSettle();
    expect(adapter.requests.single.path, '/api/emails/1/restore');
    expect(changed!.isTrashed, isFalse);
  });

  testWidgets('non-trashed email hides restore', (tester) async {
    final email = EmailItem.fromJson(fixtureMap('email_item'));
    await pumpScreen(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: EmailDetailView(email: email, onChanged: (_) {}),
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.text('Restore from Trash'), findsNothing);
    expect(find.text('Mark done'), findsOneWidget);
  });
}
