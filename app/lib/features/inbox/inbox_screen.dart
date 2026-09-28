import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/guard.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/tab_scaffold.dart';
import '../control/scan_controller.dart';
import 'email_detail_sheet.dart';
import 'inbox_controller.dart';
import 'reclassify_sheet.dart';
import 'swipeable_email_tile.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(scanControllerProvider, (previous, next) {
      if (previous?.busy == true && !next.busy) {
        if (next.run != null && next.run!.status == ScanStatus.succeeded) {
          ref.read(inboxControllerProvider.notifier).refresh();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Scan complete · ${next.run!.processedCount} new'),
            ),
          );
        } else if (next.error != null) {
          final message = next.error is ApiException
              ? (next.error as ApiException).userMessage
              : next.error.toString();
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      }
    });

    final scanState = ref.watch(scanControllerProvider);
    final filter = ref.watch(inboxFilterProvider);
    final inboxAsync = ref.watch(inboxControllerProvider);
    final controller = ref.read(inboxControllerProvider.notifier);
    final now = ref.watch(clockProvider)();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 400) {
            controller.loadMore();
          }
        }
        return false;
      },
      child: TabScaffold(
        title: 'Inbox',
        onRefresh: () => guardAction(context, controller.refresh),
        actions: [
          IconButton(
            tooltip: 'Scan now',
            icon: const Icon(Icons.sync_rounded),
            onPressed: scanState.busy
                ? null
                : () => ref.read(scanControllerProvider.notifier).start(),
          ),
        ],
        slivers: [
          if (scanState.busy)
            const SliverToBoxAdapter(child: StatusBanner.scanRunning()),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(
                Space.gutter(context),
                Space.s2,
                Space.gutter(context),
                Space.s1,
              ),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: filter.category == null,
                    onSelected: (_) => ref
                        .read(inboxFilterProvider.notifier)
                        .setCategory(null),
                  ),
                  for (final cat in EmailCategory.values) ...[
                    const SizedBox(width: Space.s2),
                    ChoiceChip(
                      label: Text(cat.label),
                      selected: filter.category == cat,
                      onSelected: (selected) => ref
                          .read(inboxFilterProvider.notifier)
                          .setCategory(selected ? cat : null),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.gutter(context)),
              child: SwitchListTile(
                title: Text('Show done', style: context.text.labelLarge),
                value: filter.showDone,
                onChanged: (val) =>
                    ref.read(inboxFilterProvider.notifier).setShowDone(val),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ...inboxAsync.when(
            loading: () => [
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: Space.gutter(context),
                  vertical: Space.s2,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: Space.s3),
                      child: EmailTileSkeleton(),
                    ),
                    childCount: 5,
                  ),
                ),
              ),
            ],
            error: (e, st) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(
                  error: e,
                  onRetry: () => ref.invalidate(inboxControllerProvider),
                ),
              ),
            ],
            data: (state) {
              if (state.items.isEmpty) {
                final String title;
                final String body;
                if (filter.category == null) {
                  title = 'All clear';
                  body = "Sentinel hasn't filed anything here yet.";
                } else if (filter.category == EmailCategory.urgentActionable) {
                  title = 'Nothing urgent';
                  body = 'Enjoy the quiet.';
                } else {
                  title = 'Nothing here';
                  body = 'No ${filter.category!.label} emails right now.';
                }
                return [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.inbox_rounded,
                      title: title,
                      body: body,
                    ),
                  ),
                ];
              }

              final widgets = <Widget>[];
              String? currentBucket;
              for (final email in state.items) {
                // The feed is ordered by when Sentinel filed each email, so
                // group by filing day too (received time is shown per tile).
                final bucket = dayBucket(
                  email.createdAt ?? email.timestamp ?? now,
                  now,
                ).toUpperCase();
                if (bucket != currentBucket) {
                  currentBucket = bucket;
                  widgets.add(
                    Padding(
                      padding: const EdgeInsets.only(
                        top: Space.s4,
                        bottom: Space.s2,
                      ),
                      child: Text(
                        bucket,
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }
                widgets.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: SwipeableEmailTile(
                      email: email,
                      onTap: () => showEmailDetailSheet(
                        context,
                        email,
                        onChanged: controller.replace,
                      ),
                      onDone: () async {
                        final ok = await guardAction(
                          context,
                          () => controller.setDone(email, true),
                        );
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Marked done'),
                              duration: const Duration(seconds: 5),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () => guardAction(
                                  context,
                                  () => controller.setDone(email, false),
                                ),
                              ),
                            ),
                          );
                        }
                        return ok;
                      },
                      onReclassify: () async {
                        final selected = await showReclassifySheet(
                          context,
                          email.category,
                        );
                        if (selected != null &&
                            selected != email.category &&
                            context.mounted) {
                          await guardAction(
                            context,
                            () => controller.reclassify(email, selected),
                          );
                        }
                      },
                    ),
                  ),
                );
              }

              if (state.loadingMore) {
                widgets.add(
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Space.s4),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                );
              }

              return [
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: Space.gutter(context),
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => widgets[index],
                      childCount: widgets.length,
                    ),
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}
