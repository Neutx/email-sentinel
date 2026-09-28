import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const SentinelApp());
    expect(find.text('Sentinel'), findsOneWidget);
  });
}
