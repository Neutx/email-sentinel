import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/guard.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/markdown_body.dart';
import '../../widgets/skeleton.dart';

class BriefingHistoryScreen extends ConsumerWidget {
  const BriefingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefingsAsync = ref.watch(briefingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Past briefings')),
      body: briefingsAsync.when(
        data: (briefings) {
          if (briefings.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'No past briefings',
              body: 'Past briefings will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => guardAction(context, () async {
              ref.invalidate(briefingsProvider);
              await ref.read(briefingsProvider.future);
            }),
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: Space.gutter(context),
                vertical: Space.s4,
              ),
              itemCount: briefings.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: Space.s3),
              itemBuilder: (context, index) =>
                  _BriefingHistoryCard(briefing: briefings[index]),
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
                  SkeletonBox(width: 80, height: 20, radius: Radii.chip),
                  SizedBox(height: Space.s2),
                  SkeletonBox(width: double.infinity, height: 20, radius: 4),
                  SizedBox(height: Space.s2),
                  SkeletonBox(width: double.infinity, height: 14, radius: 4),
                ],
              ),
            ),
          ),
        ),
        error: (err, _) => ErrorState(
          error: err,
          onRetry: () => ref.invalidate(briefingsProvider),
        ),
      ),
    );
  }
}

class _BriefingHistoryCard extends ConsumerStatefulWidget {
  const _BriefingHistoryCard({required this.briefing});

  final Briefing briefing;

  @override
  ConsumerState<_BriefingHistoryCard> createState() =>
      _BriefingHistoryCardState();
}

class _BriefingHistoryCardState extends ConsumerState<_BriefingHistoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final briefing = widget.briefing;
    final now = ref.watch(clockProvider)();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    constraints: const BoxConstraints(minHeight: 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.s2,
                      vertical: Space.s1,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Text(
                      briefing.periodLabel,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Text(
                    '·',
                    style: context.text.labelMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Text(
                    relativeTime(briefing.createdAt, now),
                    style: context.text.labelMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: context.colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: Space.s2),
              Text(briefing.title, style: context.text.titleLarge),
              const SizedBox(height: Space.s2),
              if (!_expanded)
                Text(
                  briefing.summary,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              else
                MarkdownBody(data: briefing.bodyMarkdown),
            ],
          ),
        ),
      ),
    );
  }
}
