import 'package:flutter/material.dart';

import '../../widgets/tab_scaffold.dart';

/// Phase 1 placeholder. Replaced in the phase that builds the Control tab
/// (docs/plans/2026-09-28-sentinel-mobile-plan.md).
class ControlScreen extends StatelessWidget {
  const ControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabScaffold(
      title: 'Control',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Icon(Icons.tune_rounded, size: 48)),
        ),
      ],
    );
  }
}
