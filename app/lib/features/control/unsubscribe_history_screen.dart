import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/time_format.dart';
import '../../data/providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';

class UnsubscribeHistoryScreen extends ConsumerWidget {
  const UnsubscribeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unsubscribesAsync = ref.watch(unsubscribesProvider);
    final now = ref.watch(clockProvider)();
    final gutter = Space.gutter(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Unsubscribe history')),
      body: unsubscribesAsync.when(
        loading: () => ListView.separated(
          padding: EdgeInsets.all(gutter),
          itemCount: 5,
          separatorBuilder: (context, index) =>
              const SizedBox(height: Space.s2),
          itemBuilder: (context, index) =>
              const SkeletonBox(width: double.infinity, height: 72),
        ),
        error: (err, stack) => ErrorState(
          error: err,
          onRetry: () => ref.invalidate(unsubscribesProvider),
        ),
        data: (logs) {
          if (logs.isEmpty) {
            return const EmptyState(
              icon: Icons.unsubscribe_outlined,
              title: 'No unsubscribes yet',
              body: 'Automated unsubscribe attempts will appear here.',
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              gutter,
              Space.s4,
              gutter,
              NavMetrics.contentBottomPadding(context),
            ),
            itemCount: logs.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: Space.s2),
            itemBuilder: (context, index) {
              final log = logs[index];
              final title = log.senderEmail.isNotEmpty
                  ? log.senderEmail
                  : log.domain;
              final timeStr = log.attemptedAt != null
                  ? relativeTime(log.attemptedAt!, now)
                  : '–';
              final subtitle =
                  '${log.method} · HTTP ${log.httpStatus ?? '–'} · $timeStr';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        log.success
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: log.success
                            ? context.sentinelColors.success
                            : context.colors.error,
                        size: 24,
                      ),
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: context.text.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: Space.s1),
                            Text(
                              subtitle,
                              style: context.text.bodyMedium?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            if (!log.success &&
                                log.errorMessage != null &&
                                log.errorMessage!.isNotEmpty) ...[
                              const SizedBox(height: Space.s1),
                              Text(
                                log.errorMessage!,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.colors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
