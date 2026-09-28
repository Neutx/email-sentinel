import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'glass_nav_bar.dart';

/// Count shown on the Inbox tab badge. Phase 2 replaces this with the number
/// of open urgent emails.
final inboxBadgeProvider = Provider<int>((ref) => 0);

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
