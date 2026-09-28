import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
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
import '../../widgets/tab_scaffold.dart';
import '../../widgets/urgency_pips.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final now = ref.watch(clockProvider)();

    return TabScaffold(
      title: 'Projects',
      onRefresh: () => guardAction(context, () async {
        ref.invalidate(projectsProvider);
        await ref.read(projectsProvider.future);
      }),
      slivers: [
        projectsAsync.when(
          data: (projects) {
            if (projects.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.account_tree_rounded,
                  title: 'No projects yet',
                  body: 'Project updates from GitHub, CI and clients appear here.',
                ),
              );
            }

            return SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: Space.gutter(context),
                vertical: Space.s4,
              ),
              sliver: SliverList.separated(
                itemCount: projects.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Space.s3),
                itemBuilder: (context, index) {
                  final project = projects[index];
                  return _ProjectCard(project: project, now: now);
                },
              ),
            );
          },
          loading: () => SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: Space.gutter(context),
              vertical: Space.s4,
            ),
            sliver: SliverList.separated(
              itemCount: 4,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: Space.s3),
              itemBuilder: (context, index) => const Card(
                child: Padding(
                  padding: EdgeInsets.all(Space.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SkeletonBox(width: 140, height: 18, radius: 4),
                          Spacer(),
                          SkeletonBox(
                            width: 24,
                            height: 20,
                            radius: Radii.chip,
                          ),
                        ],
                      ),
                      SizedBox(height: Space.s2),
                      Row(
                        children: [
                          SkeletonBox(width: 100, height: 14, radius: 4),
                          Spacer(),
                          SkeletonBox(width: 32, height: 12, radius: 2),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          error: (err, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              error: err,
              onRetry: () => ref.invalidate(projectsProvider),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.now});

  final ProjectSummary project;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final count = project.updateCount;
    final updates = '$count ${count == 1 ? 'update' : 'updates'}';
    final metaText = project.lastUpdateAt != null
        ? '$updates · ${relativeTime(project.lastUpdateAt!, now)}'
        : updates;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.project(project.name)),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      style: context.text.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (project.openActions > 0) ...[
                    const SizedBox(width: Space.s2),
                    Semantics(
                      container: true,
                      label: '${project.openActions} open actions',
                      child: ExcludeSemantics(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.s2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.sentinelColors.caution.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(Radii.chip),
                          ),
                          child: Text(
                            '${project.openActions}',
                            style: context.text.labelMedium?.copyWith(
                              color: context.sentinelColors.caution,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Space.s2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      metaText,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  UrgencyPips(urgency: project.maxUrgency),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
