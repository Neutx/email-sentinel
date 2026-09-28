import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/network/api_exception.dart';
import 'package:sentinel/widgets/empty_state.dart';
import 'package:sentinel/widgets/error_state.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('offline error mentions Tailscale and retries', (tester) async {
    var retried = 0;
    await pumpScreen(
      tester,
      Scaffold(
        body: ErrorState(
          error: const ApiException(ApiErrorKind.offline, ''),
          onRetry: () => retried++,
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.textContaining('Tailscale'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('unauthorized error offers Reconnect', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: ErrorState(
          error: const ApiException(ApiErrorKind.unauthorized, ''),
          onRetry: () {},
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('empty state renders title and body', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: EmptyState(
          icon: Icons.inbox_rounded,
          title: 'All clear',
          body: 'Nothing to triage.',
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('Nothing to triage.'), findsOneWidget);
  });
}
