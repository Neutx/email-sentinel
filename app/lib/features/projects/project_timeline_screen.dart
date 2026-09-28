import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/guard.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';
import '../inbox/email_detail_sheet.dart';
import '../inbox/inbox_controller.dart';

Color _urgencyColor(BuildContext context, int urgency) {
  if (urgency >= 5) return context.colors.error;
  if (urgency == 4) return context.sentinelColors.caution;
  if (urgency == 3) return context.colors.primary;
  return context.colors.onSurfaceVariant;
}

class ProjectTimelineScreen extends ConsumerWidget {
  const ProjectTimelineScreen({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesAsync = ref.watch(projectUpdatesProvider(name));
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: updatesAsync.when(
        data: (updates) {
          if (updates.isEmpty) {
            return const EmptyState(
              icon: Icons.timeline_rounded,
              title: 'No updates yet',
              body: 'No activity recorded for this project.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => guardAction(context, () async {
              ref.invalidate(projectUpdatesProvider(name));
              await ref.read(projectUpdatesProvider(name).future);
            }),
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: Space.gutter(context),
                vertical: Space.s4,
              ),
              itemCount: updates.length,
              itemBuilder: (context, index) {
                final update = updates[index];
                final isFirst = index == 0;
                final isLast = index == updates.length - 1;
                return _TimelineNodeTile(
                  update: update,
                  now: now,
                  projectName: name,
                  isFirst: isFirst,
                  isLast: isLast,
                );
              },
            ),
          );
        },
        loading: () => ListView.separated(
          padding: EdgeInsets.symmetric(
            horizontal: Space.gutter(context),
            vertical: Space.s4,
          ),
          itemCount: 4,
          separatorBuilder: (context, index) =>
              const SizedBox(height: Space.s3),
          itemBuilder: (context, index) => const Card(
            child: Padding(
              padding: EdgeInsets.all(Space.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 80, height: 14, radius: 4),
                  SizedBox(height: Space.s2),
                  SkeletonBox(width: double.infinity, height: 18, radius: 4),
                  SizedBox(height: Space.s2),
                  SkeletonBox(width: double.infinity, height: 14, radius: 4),
                ],
              ),
            ),
          ),
        ),
        error: (err, _) => ErrorState(
          error: err,
          onRetry: () => ref.invalidate(projectUpdatesProvider(name)),
        ),
      ),
    );
  }
}

class _TimelineNodeTile extends ConsumerWidget {
  const _TimelineNodeTile({
    required this.update,
    required this.now,
    required this.projectName,
    required this.isFirst,
    required this.isLast,
  });

  final ProjectUpdate update;
  final DateTime now;
  final String projectName;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dotColor = _urgencyColor(context, update.urgency);
    final time = update.receivedAt ?? update.createdAt;

    Widget content = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: update.emailId == null
            ? null
            : () async {
                await guardAction(context, () async {
                  final email = await ref
                      .read(repositoryProvider)
                      .email(update.emailId!);
                  if (context.mounted) {
                    await showEmailDetailSheet(
                      context,
                      email,
                      onChanged: (_) {
                        ref.invalidate(projectUpdatesProvider(projectName));
                        ref.invalidate(projectsProvider);
                        ref.invalidate(openUrgentCountProvider);
                      },
                    );
                  }
                });
              },
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (time != null)
                Text(
                  relativeTime(time, now),
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              if (update.subject != null && update.subject!.isNotEmpty) ...[
                const SizedBox(height: Space.s1),
                Text(update.subject!, style: context.text.titleMedium),
              ],
              if (update.summary != null && update.summary!.isNotEmpty) ...[
                const SizedBox(height: Space.s1),
                Text(
                  update.summary!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (update.actionRequired &&
                  update.actionDescription != null &&
                  update.actionDescription!.isNotEmpty) ...[
                const SizedBox(height: Space.s2),
                Container(
                  padding: const EdgeInsets.all(Space.s3),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.task_alt_rounded,
                        size: 18,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: Text(
                          update.actionDescription!,
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (update.isDone) {
      content = Opacity(opacity: 0.6, child: content);
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // Rail line
                Positioned(
                  top: isFirst ? 18 : 0,
                  bottom: isLast ? 18 : 0,
                  child: Container(
                    width: 2,
                    color: context.colors.outlineVariant,
                  ),
                ),
                // Indicator Dot
                Positioned(
                  top: 14,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.colors.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
