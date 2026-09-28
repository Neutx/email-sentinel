import 'package:flutter/material.dart';

import '../network/api_exception.dart';

/// Runs a user-triggered [action]. On failure shows the API's user-facing
/// message in a snackbar instead of letting the exception escape (which would
/// otherwise crash gesture callbacks like Dismissible.confirmDismiss).
/// Returns whether the action succeeded.
Future<bool> guardAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) {
      final message = e is ApiException
          ? e.userMessage
          : 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    return false;
  }
}
