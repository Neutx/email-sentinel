import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/error_state.dart';
import '../../widgets/urgency_pips.dart';
import 'reclassify_sheet.dart';

class EmailDetailView extends ConsumerStatefulWidget {
  const EmailDetailView({
    required this.email,
    required this.onChanged,
    super.key,
  });

  final EmailItem email;
  final ValueChanged<EmailItem> onChanged;

  @override
  ConsumerState<EmailDetailView> createState() => _EmailDetailViewState();
}

class _EmailDetailViewState extends ConsumerState<EmailDetailView> {
  late EmailItem _email;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _email = widget.email;
  }

  @override
  void didUpdateWidget(EmailDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.email != oldWidget.email) {
      _email = widget.email;
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    final message = e is ApiException
        ? e.userMessage
        : 'Something went wrong. Please try again.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleDone() async {
    setState(() => _busyAction = 'done');
    try {
      await ref.read(connectionProvider.future);
      final res = await ref
          .read(repositoryProvider)
          .setDone(_email.id, done: !_email.isDone);
      final updated = res.email ?? _email.copyWith(isDone: !_email.isDone);
      if (mounted) {
        setState(() => _email = updated);
      }
      widget.onChanged(updated);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _reclassify() async {
    final selected = await showReclassifySheet(context, _email.category);
    if (selected == null || selected == _email.category || !mounted) return;

    setState(() => _busyAction = 'reclassify');
    try {
      await ref.read(connectionProvider.future);
      final res = await ref
          .read(repositoryProvider)
          .reclassify(_email.id, selected);
      final updated = res.email ?? _email.copyWith(category: selected);
      if (mounted) {
        setState(() => _email = updated);
      }
      widget.onChanged(updated);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _protectSender() async {
    setState(() => _busyAction = 'protect');
    try {
      await ref.read(connectionProvider.future);
      final res = await ref.read(repositoryProvider).protectSender(_email.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.message.isNotEmpty ? res.message : 'Sender protected',
            ),
          ),
        );
        if (res.email != null) {
          setState(() => _email = res.email!);
          widget.onChanged(res.email!);
        }
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _busyAction = 'restore');
    try {
      await ref.read(connectionProvider.future);
      final res = await ref.read(repositoryProvider).restore(_email.id);
      final updated = res.email ?? _email.copyWith(isTrashed: false);
      if (mounted) {
        setState(() => _email = updated);
        if (res.message.isNotEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(res.message)));
        }
      }
      widget.onChanged(updated);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CategoryChip(category: _email.category),
            const SizedBox(width: Space.s2),
            UrgencyPips(urgency: _email.urgency),
            if (_email.projectName != null &&
                _email.projectName!.isNotEmpty) ...[
              const SizedBox(width: Space.s2),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s2,
                    vertical: Space.s1,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(Radii.chip),
                  ),
                  child: Text(
                    _email.projectName!,
                    style: context.text.labelMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (_email.timestamp != null)
              Text(
                relativeTime(_email.timestamp!, now),
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.s4),
        Text(_email.subject, style: context.text.titleLarge),
        const SizedBox(height: Space.s2),
        Text(
          'From: ${_email.sender.isNotEmpty ? _email.sender : _email.senderEmail}',
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        if (_email.actionRequired ||
            (_email.actionDescription != null &&
                _email.actionDescription!.isNotEmpty)) ...[
          const SizedBox(height: Space.s3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.s3),
            decoration: BoxDecoration(
              color: context.colors.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.task_alt_rounded,
                  size: 20,
                  color: context.colors.primary,
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text(
                    _email.actionDescription != null &&
                            _email.actionDescription!.isNotEmpty
                        ? _email.actionDescription!
                        : 'Action required',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.s3),
        Text(
          _email.summary.isNotEmpty ? _email.summary : _email.subject,
          style: context.text.bodyLarge,
        ),
        const SizedBox(height: Space.s3),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s1,
          children: [
            if (_email.isTrashed)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: context.colors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: Text(
                  'Trashed',
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            if (_email.isUnsubscribed)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: context.sentinelColors.fyi.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: Text(
                  'Unsubscribed',
                  style: context.text.labelMedium?.copyWith(
                    color: context.sentinelColors.fyi,
                  ),
                ),
              ),
            if (_email.dryRun)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: context.sentinelColors.caution.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.chip),
                ),
                child: Text(
                  'Dry run',
                  style: context.text.labelMedium?.copyWith(
                    color: context.sentinelColors.caution,
                  ),
                ),
              ),
            if (_email.isDone)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: context.sentinelColors.success,
                  ),
                  const SizedBox(width: Space.s1),
                  Text(
                    'Done',
                    style: context.text.labelMedium?.copyWith(
                      color: context.sentinelColors.success,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: Space.s6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busyAction != null ? null : _toggleDone,
            child: _busyAction == 'done'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_email.isDone ? 'Mark not done' : 'Mark done'),
          ),
        ),
        const SizedBox(height: Space.s2),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busyAction != null ? null : _reclassify,
            child: _busyAction == 'reclassify'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Reclassify'),
          ),
        ),
        const SizedBox(height: Space.s2),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busyAction != null ? null : _protectSender,
            child: _busyAction == 'protect'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Protect sender'),
          ),
        ),
        if (_email.isTrashed) ...[
          const SizedBox(height: Space.s2),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _busyAction != null ? null : _restore,
              child: _busyAction == 'restore'
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Restore from Trash'),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> showEmailDetailSheet(
  BuildContext context,
  EmailItem email, {
  required ValueChanged<EmailItem> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Space.gutter(context),
            Space.s2,
            Space.gutter(context),
            Space.s6,
          ),
          child: EmailDetailView(email: email, onChanged: onChanged),
        ),
      ),
    ),
  );
}

class EmailDetailScreen extends ConsumerStatefulWidget {
  const EmailDetailScreen({required this.id, super.key});

  final int id;

  @override
  ConsumerState<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends ConsumerState<EmailDetailScreen> {
  late Future<EmailItem> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = () async {
      await ref.read(connectionProvider.future);
      return ref.read(repositoryProvider).email(widget.id);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Email')),
      body: FutureBuilder<EmailItem>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              error: snapshot.error!,
              onRetry: () => setState(_load),
            );
          }
          final email = snapshot.data!;
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(Space.gutter(context)),
              child: EmailDetailView(
                email: email,
                onChanged: (updated) {
                  setState(() {
                    _future = Future.value(updated);
                  });
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
