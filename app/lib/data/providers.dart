import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'models.dart';

final systemStatusProvider = FutureProvider<SystemStatus>((ref) async {
  await ref.watch(connectionProvider.future);
  return ref.watch(repositoryProvider).status();
});

final statsProvider = FutureProvider<Stats>((ref) async {
  await ref.watch(connectionProvider.future);
  return ref.watch(repositoryProvider).stats();
});

final latestBriefingProvider = FutureProvider<Briefing?>((ref) async {
  await ref.watch(connectionProvider.future);
  return ref.watch(repositoryProvider).latestBriefing();
});

final briefingsProvider = FutureProvider<List<Briefing>>((ref) async {
  await ref.watch(connectionProvider.future);
  return ref.watch(repositoryProvider).briefings();
});

final needsYouProvider = FutureProvider<List<EmailItem>>((ref) async {
  await ref.watch(connectionProvider.future);
  final page = await ref
      .watch(repositoryProvider)
      .emails(categories: {EmailCategory.urgentActionable}, limit: 5);
  return page.items;
});

final projectsProvider = FutureProvider<List<ProjectSummary>>((ref) async {
  await ref.watch(connectionProvider.future);
  return ref.watch(repositoryProvider).projects();
});

final projectUpdatesProvider =
    FutureProvider.family<List<ProjectUpdate>, String>((ref, name) async {
      await ref.watch(connectionProvider.future);
      return ref.watch(repositoryProvider).projectUpdates(name);
    });
