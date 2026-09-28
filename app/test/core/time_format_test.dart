import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/time_format.dart';

void main() {
  final now = DateTime(2026, 9, 28, 12);
  test('relativeTime', () {
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'now');
    expect(
      relativeTime(now.subtract(const Duration(minutes: 5)), now),
      '5 min ago',
    );
    expect(
      relativeTime(now.subtract(const Duration(hours: 3)), now),
      '3 h ago',
    );
    expect(relativeTime(DateTime(2026, 9, 27, 23), now), 'Yesterday');
    expect(relativeTime(DateTime(2026, 9, 21, 9), now), 'Mon 21 Sep');
    expect(relativeTime(DateTime(2025, 9, 28, 9), now), '28 Sep 2025');
  });
  test('dayBucket', () {
    expect(dayBucket(DateTime(2026, 9, 28, 1), now), 'Today');
    expect(dayBucket(DateTime(2026, 9, 27, 23), now), 'Yesterday');
    expect(dayBucket(DateTime(2026, 9, 21), now), 'Mon 21 Sep');
  });
}
