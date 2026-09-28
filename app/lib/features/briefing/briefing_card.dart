import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../widgets/markdown_body.dart';

class BriefingCard extends ConsumerStatefulWidget {
  const BriefingCard({required this.briefing, super.key});

  final Briefing briefing;

  @override
  ConsumerState<BriefingCard> createState() => _BriefingCardState();
}

class _BriefingCardState extends ConsumerState<BriefingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final briefing = widget.briefing;
    final now = ref.watch(clockProvider)();
    final hasLongBody = briefing.bodyMarkdown.length > 200;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wb_twilight_rounded,
                        size: 16,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: Space.s1),
                      Text(
                        briefing.periodLabel,
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.primary,
                        ),
                      ),
                    ],
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
              ],
            ),
            const SizedBox(height: Space.s2),
            Text(briefing.title, style: context.text.titleLarge),
            const SizedBox(height: Space.s2),
            if (!_expanded && hasLongBody)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black, Colors.black, Colors.transparent],
                      stops: [0.0, 0.7, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: MarkdownBody(data: briefing.bodyMarkdown),
                ),
              )
            else
              MarkdownBody(data: briefing.bodyMarkdown),
            if (hasLongBody) ...[
              const SizedBox(height: Space.s1),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(_expanded ? 'Show less' : 'Read more'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
