import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/theme/glass.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  Future<void> pumpGlass(WidgetTester tester, {required bool reduce}) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: GlassSurface(child: SizedBox(width: 100, height: 64)),
      ),
      overrides: await testOverrides(
        adapter: FakeAdapter({}),
        prefs: {'pref.reduceTransparency': reduce},
      ),
    );
  }

  testWidgets('blurs the backdrop by default', (tester) async {
    await pumpGlass(tester, reduce: false);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('falls back to a solid surface when reduce transparency is on', (
    tester,
  ) async {
    await pumpGlass(tester, reduce: true);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
