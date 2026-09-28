import 'package:flutter/material.dart';

import '../../widgets/tab_scaffold.dart';

/// Phase 1 placeholder. Replaced in the phase that builds the Inbox tab
/// (docs/plans/2026-09-28-sentinel-mobile-plan.md).
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabScaffold(
      title: 'Inbox',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Icon(Icons.inbox_rounded, size: 48)),
        ),
      ],
    );
  }
}
