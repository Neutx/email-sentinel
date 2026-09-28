import 'package:intl/intl.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _date(DateTime t, DateTime now) => t.year == now.year
    ? DateFormat('EEE d MMM').format(t)
    : DateFormat('d MMM y').format(t);

String relativeTime(DateTime t, DateTime now) {
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'now';
  if (_sameDay(t, now) && diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (_sameDay(t, now)) return '${diff.inHours} h ago';
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return _date(t, now);
}

String dayBucket(DateTime t, DateTime now) {
  if (_sameDay(t, now)) return 'Today';
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return _date(t, now);
}
