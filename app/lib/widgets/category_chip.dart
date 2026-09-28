import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import '../data/models.dart';
import 'category_style.dart';

class CategoryChip extends StatelessWidget {
  const CategoryChip({required this.category, super.key});

  final EmailCategory category;

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(context, category);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.s1,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.color),
          const SizedBox(width: Space.s1),
          Text(
            style.label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: style.color),
          ),
        ],
      ),
    );
  }
}
