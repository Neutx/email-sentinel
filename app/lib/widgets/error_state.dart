import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/providers.dart';
import '../core/theme/sentinel_colors.dart';
import '../core/theme/tokens.dart';

class ErrorState extends ConsumerWidget {
  const ErrorState({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnauthorized =
        error is ApiException &&
        (error as ApiException).kind == ApiErrorKind.unauthorized;
    final isOffline =
        error is ApiException &&
        (error as ApiException).kind == ApiErrorKind.offline;

    final message = error is ApiException
        ? (error as ApiException).userMessage
        : 'Something went wrong. Please try again.';

    final icon = isOffline
        ? Icons.cloud_off_rounded
        : Icons.error_outline_rounded;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Space.gutter(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: context.colors.error),
            ),
            const SizedBox(height: Space.s4),
            Text(
              isOffline ? 'Offline' : 'Error',
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.s2),
            Text(
              message,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.s4),
            if (isUnauthorized)
              FilledButton(
                onPressed: () =>
                    ref.read(connectionProvider.notifier).disconnect(),
                child: const Text('Reconnect'),
              )
            else
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
