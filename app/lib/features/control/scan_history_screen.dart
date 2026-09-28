import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';

class ScanHistoryScreen extends ConsumerWidget {
  const ScanHistoryScreen({super.key});

  Color _statusColor(BuildContext context, ScanStatus status) =>
      switch (status) {
        ScanStatus.succeeded => context.sentinelColors.success,
        ScanStatus.failed => context.colors.error,
        ScanStatus.running => context.colors.primary,
        ScanStatus.abandoned => context.colors.outline,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scansAsync = ref.watch(scansProvider);
    final now = ref.watch(clockProvider)();
    final gutter = Space.gutter(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan history')),
      body: scansAsync.when(
        loading: () => ListView.separated(
          padding: EdgeInsets.all(gutter),
          itemCount: 5,
          separatorBuilder: (context, index) =>
              const SizedBox(height: Space.s2),
          itemBuilder: (context, index) =>
              const SkeletonBox(width: double.infinity, height: 80),
        ),
        error: (err, stack) => ErrorState(
          error: err,
          onRetry: () => ref.invalidate(scansProvider),
        ),
        data: (scans) {
          if (scans.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'No scans yet',
              body: 'Scan execution history will appear here.',
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              gutter,
              Space.s4,
              gutter,
              NavMetrics.contentBottomPadding(context),
            ),
            itemCount: scans.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: Space.s2),
            itemBuilder: (context, index) {
              final scan = scans[index];
              final statusColor = _statusColor(context, scan.status);
              final timeStr = relativeTime(scan.startedAt, now);
              final durationStr = scan.finishedAt != null
                  ? '${scan.finishedAt!.difference(scan.startedAt).inSeconds}s'
                  : 'running';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                scan.trigger,
                                style: context.text.titleMedium,
                              ),
                              const SizedBox(width: Space.s2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.s2,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                    Radii.control,
                                  ),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  scan.status.name.toUpperCase(),
                                  style: context.text.labelSmall?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            timeStr,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s2),
                      Text(
                        '${scan.processedCount} processed · ${scan.skippedCount} skipped · $durationStr',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      if (scan.error != null && scan.error!.isNotEmpty) ...[
                        const SizedBox(height: Space.s1),
                        Text(
                          scan.error!,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ],
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
