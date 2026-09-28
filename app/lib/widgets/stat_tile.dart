import 'package:flutter/material.dart';

import '../core/theme/sentinel_colors.dart';
import '../core/theme/tokens.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.value,
    required this.label,
    super.key,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: context.colors.primary),
              const SizedBox(height: Space.s2),
              ExcludeSemantics(
                child: Text(
                  '$value',
                  style: context.text.headlineSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: Space.s1),
              ExcludeSemantics(
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
