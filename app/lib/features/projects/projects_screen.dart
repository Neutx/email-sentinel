import 'package:flutter/material.dart';

import '../../widgets/tab_scaffold.dart';

/// Phase 1 placeholder. Replaced in the phase that builds the Projects tab
/// (docs/plans/2026-09-28-sentinel-mobile-plan.md).
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabScaffold(
      title: 'Projects',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Icon(Icons.account_tree_rounded, size: 48)),
        ),
      ],
    );
  }
}
