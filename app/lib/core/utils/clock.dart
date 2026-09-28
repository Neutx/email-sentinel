import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable clock so widget tests can pin "now".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
