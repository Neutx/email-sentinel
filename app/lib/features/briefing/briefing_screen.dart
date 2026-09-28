import 'package:flutter/material.dart';

import '../../widgets/tab_scaffold.dart';

/// Phase 1 placeholder. Replaced in the phase that builds the Briefing tab
/// (docs/plans/2026-09-28-sentinel-mobile-plan.md).
class BriefingScreen extends StatelessWidget {
  const BriefingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabScaffold(
      title: 'Briefing',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Icon(Icons.wb_twilight_rounded, size: 48)),
        ),
      ],
    );
  }
}
