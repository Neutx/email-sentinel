import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';

class InboxFilter {
  const InboxFilter({this.category, this.showDone = false});
  final EmailCategory? category;
  final bool showDone;

  InboxFilter copyWith({EmailCategory? Function()? category, bool? showDone}) =>
      InboxFilter(
        category: category != null ? category() : this.category,
        showDone: showDone ?? this.showDone,
      );
}

class InboxFilterController extends Notifier<InboxFilter> {
  @override
  InboxFilter build() => const InboxFilter();

  void setCategory(EmailCategory? category) {
    state = InboxFilter(category: category, showDone: state.showDone);
  }

  void setShowDone(bool showDone) {
    state = InboxFilter(category: state.category, showDone: showDone);
  }
}

final inboxFilterProvider =
    NotifierProvider<InboxFilterController, InboxFilter>(
      InboxFilterController.new,
    );

class InboxState {
  const InboxState({
    required this.items,
    required this.nextCursor,
    this.loadingMore = false,
  });

  final List<EmailItem> items;
  final int? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;

  InboxState copyWith({
    List<EmailItem>? items,
    int? Function()? nextCursor,
    bool? loadingMore,
  }) => InboxState(
    items: items ?? this.items,
    nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

final openUrgentCountProvider = FutureProvider<int>((ref) async {
  await ref.watch(connectionProvider.future);
  final repo = ref.watch(repositoryProvider);
  final page = await repo.emails(
    categories: {EmailCategory.urgentActionable},
    limit: 99,
  );
  return page.items.length;
});

final inboxControllerProvider =
    AsyncNotifierProvider<InboxController, InboxState>(InboxController.new);

class InboxController extends AsyncNotifier<InboxState> {
  static const pageSize = 30;

  @override
  Future<InboxState> build() async {
    final filter = ref.watch(inboxFilterProvider);
    await ref.watch(connectionProvider.future);
    final repo = ref.watch(repositoryProvider);
    final page = await repo.emails(
      categories: filter.category != null ? {filter.category!} : const {},
      includeDone: filter.showDone,
      limit: pageSize,
    );
    return InboxState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> refresh() async {
    final filter = ref.read(inboxFilterProvider);
    await ref.read(connectionProvider.future);
    final repo = ref.read(repositoryProvider);
    final page = await repo.emails(
      categories: filter.category != null ? {filter.category!} : const {},
      includeDone: filter.showDone,
      limit: pageSize,
    );
    state = AsyncData(
      InboxState(items: page.items, nextCursor: page.nextCursor),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final filter = ref.read(inboxFilterProvider);
      await ref.read(connectionProvider.future);
      final repo = ref.read(repositoryProvider);
      final page = await repo.emails(
        categories: filter.category != null ? {filter.category!} : const {},
        includeDone: filter.showDone,
        limit: pageSize,
        beforeId: current.nextCursor,
      );
      state = AsyncData(
        InboxState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
          loadingMore: false,
        ),
      );
    } catch (e) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
    }
  }

  Future<void> setDone(EmailItem email, bool done) async {
    final current = state.value;
    if (current == null) return;

    final filter = ref.read(inboxFilterProvider);
    final oldItems = current.items;

    List<EmailItem> newItems;
    if (!filter.showDone) {
      if (done) {
        newItems = oldItems.where((e) => e.id != email.id).toList();
      } else {
        final updatedEmail = email.copyWith(isDone: false);
        final list = List<EmailItem>.from(oldItems);
        final index = list.indexWhere((e) => e.id < email.id);
        if (index == -1) {
          list.add(updatedEmail);
        } else {
          list.insert(index, updatedEmail);
        }
        newItems = list;
      }
    } else {
      newItems = oldItems.map((e) {
        if (e.id == email.id) {
          return e.copyWith(isDone: done);
        }
        return e;
      }).toList();
    }

    state = AsyncData(current.copyWith(items: newItems));

    try {
      await ref.read(connectionProvider.future);
      final repo = ref.read(repositoryProvider);
      await repo.setDone(email.id, done: done);
      ref.invalidate(openUrgentCountProvider);
    } catch (e) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(items: oldItems));
      }
      rethrow;
    }
  }

  Future<void> reclassify(EmailItem email, EmailCategory category) async {
    final current = state.value;
    if (current == null) return;

    final filter = ref.read(inboxFilterProvider);
    final oldItems = current.items;

    List<EmailItem> newItems;
    if (filter.category != null && filter.category != category) {
      newItems = oldItems.where((e) => e.id != email.id).toList();
    } else {
      newItems = oldItems.map((e) {
        if (e.id == email.id) {
          return e.copyWith(category: category);
        }
        return e;
      }).toList();
    }

    state = AsyncData(current.copyWith(items: newItems));

    try {
      await ref.read(connectionProvider.future);
      final repo = ref.read(repositoryProvider);
      await repo.reclassify(email.id, category);
      ref.invalidate(openUrgentCountProvider);
    } catch (e) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(items: oldItems));
      }
      rethrow;
    }
  }

  void replace(EmailItem updated) {
    final current = state.value;
    if (current == null) return;

    final filter = ref.read(inboxFilterProvider);
    if (!filter.showDone && updated.isDone) {
      state = AsyncData(
        current.copyWith(
          items: current.items.where((e) => e.id != updated.id).toList(),
        ),
      );
      ref.invalidate(openUrgentCountProvider);
      return;
    }
    if (filter.category != null && updated.category != filter.category) {
      state = AsyncData(
        current.copyWith(
          items: current.items.where((e) => e.id != updated.id).toList(),
        ),
      );
      ref.invalidate(openUrgentCountProvider);
      return;
    }

    state = AsyncData(
      current.copyWith(
        items: current.items
            .map((e) => e.id == updated.id ? updated : e)
            .toList(),
      ),
    );
    ref.invalidate(openUrgentCountProvider);
  }
}
