import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/preferences/app_preferences.dart';
import 'package:sentinel/core/providers.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/features/control/lists_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  final now = DateTime(2026, 9, 28, 20, 0);

  Future<List<Override>> baseOverrides({required FakeAdapter adapter}) async {
    SharedPreferences.setMockInitialValues(const {});
    final sharedPrefs = await SharedPreferences.getInstance();
    return [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      connectionStoreProvider.overrideWithValue(
        MemoryConnectionStore(testConfig),
      ),
      apiClientFactoryProvider.overrideWithValue(
        (config) => fakeClient(adapter, config),
      ),
      clockProvider.overrideWithValue(() => now),
    ];
  }

  group('ListsEditorScreen - Protected senders', () {
    testWidgets('renders title, helper text, and existing chips', (
      tester,
    ) async {
      final adapter = FakeAdapter({
        'GET /api/settings': const FakeResponse.fixture('settings'),
      });

      await pumpScreen(
        tester,
        const ListsEditorScreen(kind: ListKind.protected),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.text('Protected senders'), findsOneWidget);
      expect(
        find.text(
          'Emails from these senders or domains are never unsubscribed or trashed.',
        ),
        findsOneWidget,
      );
      expect(find.text('github.com'), findsOneWidget);
      expect(find.text('stripe.com'), findsOneWidget);
    });

    testWidgets(
      'adding Example.COM  trims, lowercases, and sends PATCH with example.com',
      (tester) async {
        final initialSettings = fixtureMap('settings');
        final currentList =
            (initialSettings['protected_domains']! as List<Object?>)
                .cast<String>();
        final updatedSettings = Map<String, Object?>.from(initialSettings)
          ..['protected_domains'] = [...currentList, 'example.com'];

        final adapter = FakeAdapter({
          'GET /api/settings': FakeResponse(initialSettings),
          'PATCH /api/settings': FakeResponse(updatedSettings),
        });

        await pumpScreen(
          tester,
          const ListsEditorScreen(kind: ListKind.protected),
          overrides: await baseOverrides(adapter: adapter),
        );

        final inputField = find.byType(TextField);
        await tester.enterText(inputField, '  Example.COM  ');
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();

        final patchReq = adapter.requests.firstWhere(
          (r) => r.method == 'PATCH' && r.path == '/api/settings',
        );
        final patchList =
            (patchReq.data as Map<String, Object?>)['protected_domains']!
                as List<dynamic>;
        expect(patchList, contains('example.com'));
        expect(find.text('example.com'), findsOneWidget);
      },
    );

    testWidgets('deleting a chip removes it and sends PATCH', (tester) async {
      final initialSettings = fixtureMap('settings');
      final currentList =
          (initialSettings['protected_domains']! as List<Object?>)
              .cast<String>();
      final updatedList = currentList.where((d) => d != 'stripe.com').toList();
      final updatedSettings = Map<String, Object?>.from(initialSettings)
        ..['protected_domains'] = updatedList;

      final adapter = FakeAdapter({
        'GET /api/settings': FakeResponse(initialSettings),
        'PATCH /api/settings': FakeResponse(updatedSettings),
      });

      await pumpScreen(
        tester,
        const ListsEditorScreen(kind: ListKind.protected),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.text('stripe.com'), findsOneWidget);

      // Find the delete button on stripe.com chip
      final deleteBtn = find.byTooltip('Remove stripe.com');
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      final patchReq = adapter.requests.firstWhere(
        (r) => r.method == 'PATCH' && r.path == '/api/settings',
      );
      final patchList =
          (patchReq.data as Map<String, Object?>)['protected_domains']!
              as List<dynamic>;
      expect(patchList, isNot(contains('stripe.com')));
    });

    testWidgets('adding duplicate does not send PATCH', (tester) async {
      final adapter = FakeAdapter({
        'GET /api/settings': const FakeResponse.fixture('settings'),
      });

      await pumpScreen(
        tester,
        const ListsEditorScreen(kind: ListKind.protected),
        overrides: await baseOverrides(adapter: adapter),
      );

      final inputField = find.byType(TextField);
      await tester.enterText(inputField, 'github.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(adapter.requests.any((r) => r.method == 'PATCH'), isFalse);
    });

    testWidgets('add failure shows error snackbar', (tester) async {
      final adapter = FakeAdapter({
        'GET /api/settings': const FakeResponse.fixture('settings'),
        'PATCH /api/settings': const FakeResponse({
          'detail': 'Server error',
        }, status: 500),
      });

      await pumpScreen(
        tester,
        const ListsEditorScreen(kind: ListKind.protected),
        overrides: await baseOverrides(adapter: adapter),
      );

      final inputField = find.byType(TextField);
      await tester.enterText(inputField, 'newdomain.org');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('ListsEditorScreen - Project keywords', () {
    testWidgets('renders title, helper text, and keyword chips', (
      tester,
    ) async {
      final adapter = FakeAdapter({
        'GET /api/settings': const FakeResponse.fixture('settings'),
      });

      await pumpScreen(
        tester,
        const ListsEditorScreen(kind: ListKind.keywords),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.text('Project keywords'), findsOneWidget);
      expect(
        find.text(
          'Emails whose subject or sender contains these words are treated as project updates.',
        ),
        findsOneWidget,
      );
      expect(find.text('murphy'), findsOneWidget);
      expect(find.text('deploy'), findsOneWidget);
    });

    testWidgets('adding keyword sends PATCH with updated keywords', (
      tester,
    ) async {
      final initialSettings = fixtureMap('settings');
      final currentList =
          (initialSettings['project_keywords']! as List<Object?>)
              .cast<String>();
      final updatedSettings = Map<String, Object?>.from(initialSettings)
        ..['project_keywords'] = [...currentList, 'hotfix'];

      final adapter = FakeAdapter({
        'GET /api/settings': FakeResponse(initialSettings),
        'PATCH /api/settings': FakeResponse(updatedSettings),
      });

      await pumpScreen(
        tester,
        const ListsEditorScreen(kind: ListKind.keywords),
        overrides: await baseOverrides(adapter: adapter),
      );

      final inputField = find.byType(TextField);
      await tester.enterText(inputField, 'HOTFIX');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      final patchReq = adapter.requests.firstWhere(
        (r) => r.method == 'PATCH' && r.path == '/api/settings',
      );
      final patchList =
          (patchReq.data as Map<String, Object?>)['project_keywords']!
              as List<dynamic>;
      expect(patchList, contains('hotfix'));
    });
  });
}
