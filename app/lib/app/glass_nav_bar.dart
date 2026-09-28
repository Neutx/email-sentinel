import 'package:flutter/material.dart';

import '../core/theme/glass.dart';
import '../core/theme/sentinel_colors.dart';
import '../core/theme/tokens.dart';

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = [
  _Destination(
    Icons.wb_twilight_outlined,
    Icons.wb_twilight_rounded,
    'Briefing',
  ),
  _Destination(Icons.inbox_outlined, Icons.inbox_rounded, 'Inbox'),
  _Destination(
    Icons.account_tree_outlined,
    Icons.account_tree_rounded,
    'Projects',
  ),
  _Destination(Icons.tune_outlined, Icons.tune_rounded, 'Control'),
];

/// Floating Liquid Glass navigation pill (DESIGN_BRIEF §4.1).
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    required this.currentIndex,
    required this.onSelect,
    this.inboxBadge = 0,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final int inboxBadge;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + NavMetrics.bottomGap;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NavMetrics.sideInset,
        0,
        NavMetrics.sideInset,
        bottom,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: SizedBox(
          height: NavMetrics.height,
          child: GlassSurface(
            borderRadius: BorderRadius.circular(Radii.nav),
            child: Row(
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  Expanded(
                    child: _NavItem(
                      destination: _destinations[i],
                      selected: i == currentIndex,
                      badge: i == 1 ? inboxBadge : 0,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.primary : colors.onSurfaceVariant;
    final semanticsLabel = badge > 0
        ? '${destination.label}, $badge urgent'
        : destination.label;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              curve: Motion.enter,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s4,
                vertical: Space.s1,
              ),
              decoration: BoxDecoration(
                color: selected ? colors.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(Space.s4),
              ),
              child: Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: context.text.labelMedium?.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
