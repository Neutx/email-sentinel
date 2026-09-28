import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../core/network/api_exception.dart';
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
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/tab_scaffold.dart';
import '../inbox/email_detail_sheet.dart';
import '../inbox/email_tile.dart';
import '../inbox/inbox_controller.dart';
import 'briefing_card.dart';

class BriefingScreen extends ConsumerWidget {
  const BriefingScreen({super.key});

  static String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final systemStatusAsync = ref.watch(systemStatusProvider);
    final statsAsync = ref.watch(statsProvider);
    final latestBriefingAsync = ref.watch(latestBriefingProvider);
    final needsYouAsync = ref.watch(needsYouProvider);

    final isOffline =
        systemStatusAsync.hasError &&
        systemStatusAsync.error is ApiException &&
        (systemStatusAsync.error! as ApiException).kind == ApiErrorKind.offline;

    final isDryRun = systemStatusAsync.value?.settings.dryRun == true;

    final lastScan = systemStatusAsync.value?.lastScan;
    final lastScanTime = lastScan?.finishedAt ?? lastScan?.startedAt;
    final scanText = lastScanTime != null
        ? 'Scanned ${relativeTime(lastScanTime, now)}'
        : 'No scans yet';

    final dateScanLine = '${DateFormat('EEE d MMM').format(now)} · $scanText';

    return TabScaffold(
      title: 'Briefing',
      onRefresh: () => guardAction(context, () async {
        ref.invalidate(systemStatusProvider);
        ref.invalidate(statsProvider);
        ref.invalidate(latestBriefingProvider);
        ref.invalidate(needsYouProvider);
        await Future.wait([
          ref.read(systemStatusProvider.future),
          ref.read(statsProvider.future),
          ref.read(latestBriefingProvider.future),
          ref.read(needsYouProvider.future),
        ]);
      }),
      slivers: [
        // Status banner if offline or dry-run
        if (isOffline)
          SliverToBoxAdapter(
            child: StatusBanner.offline(
              onRetry: () => ref.invalidate(systemStatusProvider),
            ),
          )
        else if (isDryRun)
          const SliverToBoxAdapter(child: StatusBanner.dryRun()),

        // Greeting + Date / scan subtitle
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Space.gutter(context),
              Space.s4,
              Space.gutter(context),
              Space.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting(now), style: context.text.displaySmall),
                const SizedBox(height: Space.s1),
                InkWell(
                  onTap: () => context.go(Routes.control),
                  borderRadius: BorderRadius.circular(Radii.control),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.s1),
                    child: Text(
                      dateScanLine,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Briefing Card
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Space.gutter(context),
              vertical: Space.s2,
            ),
            child: latestBriefingAsync.when(
              data: (briefing) {
                if (briefing == null) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: Space.s4),
                      child: EmptyState(
                        icon: Icons.wb_twilight_rounded,
                        title: 'No briefing yet',
                        body: 'Hermes writes one at 08:00 and 18:00.',
                      ),
                    ),
                  );
                }
                return BriefingCard(briefing: briefing);
              },
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(Space.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 80, height: 20, radius: Radii.chip),
                      SizedBox(height: Space.s2),
                      SkeletonBox(width: 200, height: 24, radius: 4),
                      SizedBox(height: Space.s2),
                      SkeletonBox(
                        width: double.infinity,
                        height: 60,
                        radius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              error: (err, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s4),
                  child: ErrorState(
                    error: err,
                    onRetry: () => ref.invalidate(latestBriefingProvider),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Needs You Section
        needsYouAsync.when(
          data: (items) {
            final count = items.length;
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Needs you ($count)',
                    actionLabel: count > 0 ? 'See all' : null,
                    onAction: () {
                      ref
                          .read(inboxFilterProvider.notifier)
                          .setCategory(EmailCategory.urgentActionable);
                      context.go(Routes.inbox);
                    },
                  ),
                ),
                if (items.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Space.gutter(context),
                        vertical: Space.s2,
                      ),
                      child: Text(
                        'Nothing needs you right now.',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Space.gutter(context),
                    ),
                    sliver: SliverList.separated(
                      itemCount: items.length > 5 ? 5 : items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: Space.s3),
                      itemBuilder: (context, index) {
                        final email = items[index];
                        return EmailTile(
                          email: email,
                          compact: true,
                          onTap: () => showEmailDetailSheet(
                            context,
                            email,
                            onChanged: (_) {
                              ref.invalidate(needsYouProvider);
                              ref.invalidate(openUrgentCountProvider);
                            },
                          ),
                          trailing: IconButton(
                            tooltip: 'Mark done',
                            icon: const Icon(Icons.check_rounded),
                            onPressed: () async {
                              await guardAction(context, () async {
                                await ref
                                    .read(repositoryProvider)
                                    .setDone(email.id, done: true);
                                ref.invalidate(needsYouProvider);
                                ref.invalidate(openUrgentCountProvider);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
          loading: () => SliverMainAxisGroup(
            slivers: [
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Needs you'),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: Space.gutter(context),
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(const [
                    EmailTileSkeleton(),
                    SizedBox(height: Space.s3),
                    EmailTileSkeleton(),
                  ]),
                ),
              ),
            ],
          ),
          error: (err, _) => SliverToBoxAdapter(
            child: ErrorState(
              error: err,
              onRetry: () => ref.invalidate(needsYouProvider),
            ),
          ),
        ),

        // At a Glance Section
        const SliverToBoxAdapter(child: SectionHeader(title: 'At a glance')),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.gutter(context)),
            child: statsAsync.when(
              data: (stats) => Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.task_alt_rounded,
                          value: stats.openActionsCount,
                          label: 'Open actions',
                        ),
                      ),
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: StatTile(
                          icon: Icons.account_tree_rounded,
                          value: stats.projectUpdatesCount,
                          label: 'Project updates',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s3),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.unsubscribe_rounded,
                          value: stats.unsubscribedCount,
                          label: 'Unsubscribed',
                        ),
                      ),
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: StatTile(
                          icon: Icons.delete_sweep_rounded,
                          value: stats.trashedCount,
                          label: 'Trashed',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              loading: () => const Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SkeletonBox(height: 80, radius: Radii.card),
                      ),
                      SizedBox(width: Space.s3),
                      Expanded(
                        child: SkeletonBox(height: 80, radius: Radii.card),
                      ),
                    ],
                  ),
                  SizedBox(height: Space.s3),
                  Row(
                    children: [
                      Expanded(
                        child: SkeletonBox(height: 80, radius: Radii.card),
                      ),
                      SizedBox(width: Space.s3),
                      Expanded(
                        child: SkeletonBox(height: 80, radius: Radii.card),
                      ),
                    ],
                  ),
                ],
              ),
              error: (err, _) => ErrorState(
                error: err,
                onRetry: () => ref.invalidate(statsProvider),
              ),
            ),
          ),
        ),

        // Past Briefings Row
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Space.gutter(context),
              Space.s4,
              Space.gutter(context),
              Space.s2,
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: Text('Past briefings', style: context.text.titleMedium),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.briefingHistory),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
