import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/app/router.dart';
import 'package:sentinel/app/routes.dart';
import 'package:sentinel/core/config/connection_config.dart';

import '../helpers/fake_api.dart';

void main() {
  const loading = AsyncLoading<ConnectionConfig?>();
  const disconnected = AsyncData<ConnectionConfig?>(null);
  const connected = AsyncData<ConnectionConfig?>(testConfig);

  test('stays on splash while the saved connection loads', () {
    expect(redirectFor(loading, Routes.splash), isNull);
    expect(redirectFor(loading, Routes.inbox), Routes.splash);
  });

  test('sends a disconnected user to Connect', () {
    expect(redirectFor(disconnected, Routes.briefing), Routes.connect);
    expect(redirectFor(disconnected, Routes.connect), isNull);
  });

  test('sends a connected user from splash/connect to Briefing', () {
    expect(redirectFor(connected, Routes.splash), Routes.briefing);
    expect(redirectFor(connected, Routes.connect), Routes.briefing);
    expect(redirectFor(connected, Routes.projects), isNull);
  });
}
