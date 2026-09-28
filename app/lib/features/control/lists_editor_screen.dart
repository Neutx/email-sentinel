import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/guard.dart';
import '../../data/models.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton.dart';
import 'settings_controller.dart';

enum ListKind { protected, keywords }

class ListsEditorScreen extends ConsumerStatefulWidget {
  const ListsEditorScreen({required this.kind, super.key});

  final ListKind kind;

  @override
  ConsumerState<ListsEditorScreen> createState() => _ListsEditorScreenState();
}

class _ListsEditorScreenState extends ConsumerState<ListsEditorScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    ListKind.protected => 'Protected senders',
    ListKind.keywords => 'Project keywords',
  };

  String get _helperText => switch (widget.kind) {
    ListKind.protected =>
      'Emails from these senders or domains are never unsubscribed or trashed.',
    ListKind.keywords => 'Emails whose subject or sender contains these words are treated as project updates.',
  };

  String get _inputLabel => switch (widget.kind) {
    ListKind.protected => 'Add sender or domain',
    ListKind.keywords => 'Add keyword',
  };

  String get _inputHint => switch (widget.kind) {
    ListKind.protected => 'e.g. stripe.com or support@client.io',
    ListKind.keywords => 'e.g. deploy or invoice',
  };

  List<String> _getItems(RuntimeSettings settings) => switch (widget.kind) {
    ListKind.protected => settings.protectedDomains,
    ListKind.keywords => settings.projectKeywords,
  };

  RuntimeSettingsPatch _buildPatch(List<String> items) => switch (widget.kind) {
    ListKind.protected => RuntimeSettingsPatch(protectedDomains: items),
    ListKind.keywords => RuntimeSettingsPatch(projectKeywords: items),
  };

  Future<void> _addItem(List<String> current) async {
    final text = _controller.text.trim().toLowerCase();
    if (text.isEmpty || current.contains(text)) return;
    _controller.clear();
    final updated = [...current, text];
    await guardAction(
      context,
      () => ref
          .read(settingsControllerProvider.notifier)
          .apply(_buildPatch(updated)),
    );
  }

  Future<void> _removeItem(List<String> current, String item) async {
    final updated = current.where((e) => e != item).toList();
    await guardAction(
      context,
      () => ref
          .read(settingsControllerProvider.notifier)
          .apply(_buildPatch(updated)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final gutter = Space.gutter(context);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: settingsAsync.when(
        loading: () => ListView(
          padding: EdgeInsets.all(gutter),
          children: const [
            SkeletonBox(width: double.infinity, height: 48),
            SizedBox(height: Space.s4),
            SkeletonBox(width: double.infinity, height: 48),
            SizedBox(height: Space.s4),
            SkeletonBox(width: double.infinity, height: 120),
          ],
        ),
        error: (err, _) => ErrorState(
          error: err,
          onRetry: () => ref.invalidate(settingsControllerProvider),
        ),
        data: (settings) {
          final items = _getItems(settings);
          return ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              Space.s4,
              gutter,
              NavMetrics.contentBottomPadding(context),
            ),
            children: [
              Text(
                _helperText,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.s6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _inputLabel,
                        hintText: _inputHint,
                      ),
                      onSubmitted: (_) => _addItem(items),
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  FilledButton(
                    onPressed: () => _addItem(items),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(80, 48),
                    ),
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: Space.s6),
              if (items.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s8),
                    child: Text(
                      'No items added yet.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: [
                    for (final item in items)
                      InputChip(
                        label: Text(item),
                        onDeleted: () => _removeItem(items, item),
                        deleteButtonTooltipMessage: 'Remove $item',
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
