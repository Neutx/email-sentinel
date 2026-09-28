import 'package:flutter/material.dart';

import '../core/theme/sentinel_colors.dart';

class UrgencyPips extends StatelessWidget {
  const UrgencyPips({required this.urgency, super.key});

  final int urgency;

  Color _filledColor(BuildContext context) {
    if (urgency >= 5) return context.colors.error;
    if (urgency == 4) return context.sentinelColors.caution;
    if (urgency == 3) return context.colors.primary;
    return context.colors.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final filledColor = _filledColor(context);
    final unfilledColor = context.colors.outlineVariant;

    return Semantics(
      label: 'Urgency $urgency of 5',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final isFilled = index < urgency;
            return Container(
              width: 4,
              height: 12,
              margin: EdgeInsets.only(right: index < 4 ? 2 : 0),
              decoration: BoxDecoration(
                color: isFilled ? filledColor : unfilledColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }
}
