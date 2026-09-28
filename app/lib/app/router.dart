import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/connection_config.dart';
import '../core/providers.dart';
import '../features/briefing/briefing_history_screen.dart';
import '../features/briefing/briefing_screen.dart';
import '../features/control/control_screen.dart';
import '../features/control/lists_editor_screen.dart';
import '../features/control/scan_history_screen.dart';
import '../features/control/unsubscribe_history_screen.dart';
import '../features/inbox/email_detail_sheet.dart';
import '../features/inbox/inbox_screen.dart';
import '../features/onboarding/connect_screen.dart';
import '../features/projects/project_timeline_screen.dart';
import '../features/projects/projects_screen.dart';
import 'app_shell.dart';
import 'routes.dart';
import 'splash_screen.dart';

/// Pure redirect logic (unit-tested in test/app/router_test.dart).
String? redirectFor(AsyncValue<ConnectionConfig?> connection, String location) {
  if (connection.isLoading && !connection.hasValue) {
    return location == Routes.splash ? null : Routes.splash;
  }
  final connected = connection.value != null;
  if (!connected) return location == Routes.connect ? null : Routes.connect;
  if (location == Routes.connect || location == Routes.splash) {
    return Routes.briefing;
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final connection = ValueNotifier<AsyncValue<ConnectionConfig?>>(
    ref.read(connectionProvider),
  );
  ref.listen(connectionProvider, (_, next) => connection.value = next);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: connection,
    redirect: (context, state) =>
        redirectFor(connection.value, state.matchedLocation),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.connect,
        builder: (context, state) => const ConnectScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.briefing,
                builder: (context, state) => const BriefingScreen(),
                routes: [
                  GoRoute(
                    path: 'history',
                    builder: (context, state) => const BriefingHistoryScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.inbox,
                builder: (context, state) => const InboxScreen(),
                routes: [
                  GoRoute(
                    path: 'email/:id',
                    builder: (context, state) => EmailDetailScreen(
                      id: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.projects,
                builder: (context, state) => const ProjectsScreen(),
                routes: [
                  GoRoute(
                    path: ':name',
                    builder: (context, state) => ProjectTimelineScreen(
                      name: Uri.decodeComponent(state.pathParameters['name']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.control,
                builder: (context, state) => const ControlScreen(),
                routes: [
                  GoRoute(
                    path: 'lists/:kind',
                    builder: (context, state) {
                      final kindParam = state.pathParameters['kind'];
                      final kind = kindParam == 'keywords'
                          ? ListKind.keywords
                          : ListKind.protected;
                      return ListsEditorScreen(kind: kind);
                    },
                  ),
                  GoRoute(
                    path: 'unsubscribes',
                    builder: (context, state) =>
                        const UnsubscribeHistoryScreen(),
                  ),
                  GoRoute(
                    path: 'scans',
                    builder: (context, state) => const ScanHistoryScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    connection.dispose();
  });
  return router;
});
