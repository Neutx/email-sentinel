import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/category_style.dart';
import '../../widgets/urgency_pips.dart';

class EmailTile extends ConsumerWidget {
  const EmailTile({
    required this.email,
    this.onTap,
    this.compact = false,
    this.trailing,
    super.key,
  });

  final EmailItem email;
  final VoidCallback? onTap;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = CategoryStyle.of(context, email.category);
    final now = ref.watch(clockProvider)();

    final content = Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CategoryChip(category: email.category),
              if (email.projectName != null &&
                  email.projectName!.isNotEmpty) ...[
                const SizedBox(width: Space.s2),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.s2,
                      vertical: Space.s1,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Text(
                      email.projectName!,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (email.timestamp != null)
                Text(
                  relativeTime(email.timestamp!, now),
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Text(
            email.senderName,
            style: context.text.labelLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.s1),
          Text(
            email.subject,
            style: context.text.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!compact && email.summary.isNotEmpty) ...[
            const SizedBox(height: Space.s1),
            Text(
              email.summary,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: Space.s2),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.s2,
                  runSpacing: Space.s1,
                  children: [
                    UrgencyPips(urgency: email.urgency),
                    if (email.isTrashed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s2,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(Radii.chip),
                        ),
                        child: Text(
                          'Trashed',
                          style: context.text.labelMedium?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ),
                    if (email.isUnsubscribed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s2,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.sentinelColors.fyi.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(Radii.chip),
                        ),
                        child: Text(
                          'Unsubscribed',
                          style: context.text.labelMedium?.copyWith(
                            color: context.sentinelColors.fyi,
                          ),
                        ),
                      ),
                    if (email.dryRun)
                      Container(
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
                          'Dry run',
                          style: context.text.labelMedium?.copyWith(
                            color: context.sentinelColors.caution,
                          ),
                        ),
                      ),
                    if (email.isDone)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: context.sentinelColors.success,
                          ),
                          const SizedBox(width: Space.s1),
                          Text(
                            'Done',
                            style: context.text.labelMedium?.copyWith(
                              color: context.sentinelColors.success,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Space.s2),
                trailing!,
              ],
            ],
          ),
        ],
      ),
    );

    Widget card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: style.color),
            ),
            content,
          ],
        ),
      ),
    );

    if (email.isDone) {
      card = Opacity(opacity: 0.6, child: card);
    }

    return card;
  }
}
