import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/inbox/inbox_controller.dart';
import 'glass_nav_bar.dart';

/// Count shown on the Inbox tab badge: number of open urgent emails.
final inboxBadgeProvider = Provider<int>(
  (ref) => ref.watch(openUrgentCountProvider).value ?? 0,
);

/// Hosts the four tab branches with the floating glass navigation pill.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: GlassNavBar(
        currentIndex: navigationShell.currentIndex,
        inboxBadge: ref.watch(inboxBadgeProvider),
        onSelect: (index) => navigationShell.goBranch(
          index,
          // Tapping the active tab returns to its root.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
