import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/network/api_exception.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/providers.dart';
import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/guard.dart';
import '../../core/utils/time_format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/error_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/tab_scaffold.dart';
import 'connection_sheet.dart';
import 'scan_controller.dart';
import 'settings_controller.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  double? _sliderValue;

  Future<void> _refresh() async {
    ref.invalidate(systemStatusProvider);
    ref.invalidate(settingsControllerProvider);
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect from Sentinel?'),
        content: const Text("You'll need the API token to reconnect."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(connectionProvider.notifier).disconnect();
    }
  }

  Widget _buildSystemCard(
    BuildContext context,
    SystemStatus status,
    ScanState scanState,
    DateTime now,
  ) {
    final colors = context.colors;
    final sentinelColors = context.sentinelColors;
    final lastScan = status.lastScan;

    String lastScanText;
    Color? lastScanColor;
    if (lastScan != null) {
      if (lastScan.status == ScanStatus.failed) {
        lastScanText = lastScan.error ?? 'Scan failed';
        lastScanColor = colors.error;
      } else {
        lastScanText =
            '${relativeTime(lastScan.startedAt, now)} · ${lastScan.processedCount} new';
      }
    } else {
      lastScanText = 'No scans yet';
    }

    String? scanResultText;
    Color? scanResultColor;
    if (scanState.busy) {
      // scanning in progress
    } else if (scanState.error != null) {
      if (scanState.error is ApiException &&
          (scanState.error as ApiException).kind == ApiErrorKind.conflict) {
        scanResultText = 'A scan is already running';
        scanResultColor = sentinelColors.caution;
      } else if (scanState.error is ApiException) {
        scanResultText = (scanState.error as ApiException).userMessage;
        scanResultColor = colors.error;
      } else {
        scanResultText = 'Scan failed';
        scanResultColor = colors.error;
      }
    } else if (scanState.run != null) {
      scanResultText =
          'Last run: ${scanState.run!.processedCount} processed, ${scanState.run!.skippedCount} skipped';
      scanResultColor = colors.onSurfaceVariant;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: sentinelColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Space.s2),
                Text(
                  'Online · v${status.version}',
                  style: context.text.labelLarge?.copyWith(
                    color: sentinelColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s4),
            _infoRow(context, 'Mailbox', status.mailbox),
            const SizedBox(height: Space.s2),
            _infoRow(context, 'Model', status.llmModel),
            const SizedBox(height: Space.s2),
            InkWell(
              borderRadius: BorderRadius.circular(Radii.control),
              onTap: () => context.push(Routes.controlScans),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        'Last scan',
                        style: context.text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        lastScanText,
                        style: context.text.bodyMedium?.copyWith(
                          color: lastScanColor ?? colors.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.s4),
            FilledButton.icon(
              onPressed: scanState.busy
                  ? null
                  : () => ref.read(scanControllerProvider.notifier).start(),
              icon: const Icon(Icons.sync_rounded),
              label: Text(scanState.busy ? 'Scanning…' : 'Scan now'),
            ),
            if (scanState.busy) ...[
              const SizedBox(height: Space.s2),
              const LinearProgressIndicator(),
            ],
            if (scanResultText != null) ...[
              const SizedBox(height: Space.s2),
              Text(
                scanResultText,
                style: context.text.bodySmall?.copyWith(color: scanResultColor),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: context.text.bodyMedium)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(systemStatusProvider);
    final settingsAsync = ref.watch(settingsControllerProvider);
    final prefs = ref.watch(appPreferencesProvider);
    final scanState = ref.watch(scanControllerProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);
    final now = ref.watch(clockProvider)();
    final gutter = Space.gutter(context);
    final config = ref.watch(connectionProvider).value;
    final serverHost = config != null
        ? (Uri.tryParse(config.baseUrl)?.host ?? config.baseUrl)
        : 'Not connected';

    if (statusAsync.isLoading || settingsAsync.isLoading) {
      return TabScaffold(
        title: 'Control',
        onRefresh: _refresh,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(gutter),
            sliver: SliverList.list(
              children: const [
                SkeletonBox(width: double.infinity, height: 180),
                SizedBox(height: Space.s6),
                SkeletonBox(width: double.infinity, height: 240),
                SizedBox(height: Space.s6),
                SkeletonBox(width: double.infinity, height: 160),
              ],
            ),
          ),
        ],
      );
    }

    if (statusAsync.hasError || settingsAsync.hasError) {
      final error = statusAsync.error ?? settingsAsync.error!;
      return TabScaffold(
        title: 'Control',
        onRefresh: _refresh,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(error: error, onRetry: _refresh),
          ),
        ],
      );
    }

    final status = statusAsync.value!;
    final settings = settingsAsync.value!;
    final currentSliderVal =
        _sliderValue ?? settings.minUrgencyToNotify.toDouble();

    return TabScaffold(
      title: 'Control',
      onRefresh: _refresh,
      slivers: [
        if (settings.dryRun)
          const SliverToBoxAdapter(child: StatusBanner.dryRun()),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            Space.s4,
            gutter,
            NavMetrics.contentBottomPadding(context),
          ),
          sliver: SliverList.list(
            children: [
              // 1. System
              _buildSystemCard(context, status, scanState, now),
              const SizedBox(height: Space.s6),

              // 2. Automation
              const SectionHeader(title: 'Automation'),
              SwitchListTile(
                title: const Text('Dry run'),
                subtitle: const Text(
                  'Simulate — nothing is trashed or unsubscribed',
                ),
                secondary: Icon(
                  Icons.science_outlined,
                  color: settings.dryRun
                      ? context.sentinelColors.caution
                      : null,
                ),
                value: settings.dryRun,
                onChanged: (v) => guardAction(
                  context,
                  () => ref
                      .read(settingsControllerProvider.notifier)
                      .apply(RuntimeSettingsPatch(dryRun: v)),
                ),
              ),
              SwitchListTile(
                title: const Text('Auto-unsubscribe'),
                subtitle: const Text(
                  'Unsubscribe from detected marketing newsletters',
                ),
                secondary: const Icon(Icons.unsubscribe_outlined),
                value: settings.autoUnsubscribe,
                onChanged: (v) => guardAction(
                  context,
                  () => ref
                      .read(settingsControllerProvider.notifier)
                      .apply(RuntimeSettingsPatch(autoUnsubscribe: v)),
                ),
              ),
              SwitchListTile(
                title: const Text('Auto-trash marketing'),
                subtitle: const Text(
                  'Move marketing emails to trash automatically',
                ),
                secondary: const Icon(Icons.delete_sweep_outlined),
                value: settings.autoDeleteMarketing,
                onChanged: (v) => guardAction(
                  context,
                  () => ref
                      .read(settingsControllerProvider.notifier)
                      .apply(RuntimeSettingsPatch(autoDeleteMarketing: v)),
                ),
              ),
              SwitchListTile(
                title: const Text('Mark processed as read'),
                subtitle: const Text('Mark emails as read once triaged'),
                secondary: const Icon(Icons.mark_email_read_outlined),
                value: settings.autoMarkReadProcessed,
                onChanged: (v) => guardAction(
                  context,
                  () => ref
                      .read(settingsControllerProvider.notifier)
                      .apply(RuntimeSettingsPatch(autoMarkReadProcessed: v)),
                ),
              ),
              const SizedBox(height: Space.s6),

              // 3. Notifications
              const SectionHeader(title: 'Notifications'),
              SwitchListTile(
                title: const Text('Background alerts'),
                subtitle: const Text(
                  'Check for urgent emails periodically in the background',
                ),
                secondary: const Icon(Icons.notifications_active_outlined),
                value: prefs.backgroundAlerts,
                onChanged: (v) async {
                  await ref
                      .read(appPreferencesProvider.notifier)
                      .setBackgroundAlerts(v);
                  if (v) {
                    await ref
                        .read(notificationServiceProvider)
                        .requestPermission();
                  }
                },
              ),
              SwitchListTile(
                title: const Text('Urgent emails'),
                subtitle: const Text('Alert on urgent and actionable emails'),
                secondary: const Icon(Icons.priority_high_rounded),
                value: settings.notifyOnUrgent,
                onChanged: (v) => guardAction(
                  context,
                  () => ref
                      .read(settingsControllerProvider.notifier)
                      .apply(RuntimeSettingsPatch(notifyOnUrgent: v)),
                ),
              ),
              SwitchListTile(
                title: const Text('Project updates'),
                subtitle: const Text('Alert on project activity and mentions'),
                secondary: const Icon(Icons.account_tree_outlined),
                value: settings.notifyOnProjectUpdates,
                onChanged: (v) => guardAction(
                  context,
                  () => ref
                      .read(settingsControllerProvider.notifier)
                      .apply(RuntimeSettingsPatch(notifyOnProjectUpdates: v)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Minimum urgency to notify',
                          style: context.text.bodyMedium,
                        ),
                        Text(
                          '${currentSliderVal.round()}',
                          style: context.text.titleMedium?.copyWith(
                            color: context.colors.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '${currentSliderVal.round()}',
                      value: currentSliderVal.clamp(1.0, 5.0),
                      onChanged: (v) => setState(() => _sliderValue = v),
                      onChangeEnd: (v) => guardAction(
                        context,
                        () => ref
                            .read(settingsControllerProvider.notifier)
                            .apply(
                              RuntimeSettingsPatch(
                                minUrgencyToNotify: v.round(),
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s6),

              // 4. Lists
              const SectionHeader(title: 'Lists'),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(
                  'Protected senders (${settings.protectedDomains.length})',
                ),
                subtitle: const Text('Never unsubscribed or trashed'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.controlListProtected),
              ),
              ListTile(
                leading: const Icon(Icons.tag_rounded),
                title: Text(
                  'Project keywords (${settings.projectKeywords.length})',
                ),
                subtitle: const Text('Keywords treated as project updates'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.controlListKeywords),
              ),
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Unsubscribe history'),
                subtitle: const Text('Audit log of unsubscribe attempts'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.controlUnsubscribes),
              ),
              const SizedBox(height: Space.s6),

              // 5. Appearance
              const SectionHeader(title: 'Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s2,
                ),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {prefs.themeMode},
                  onSelectionChanged: (modes) => ref
                      .read(appPreferencesProvider.notifier)
                      .setThemeMode(modes.first),
                ),
              ),
              SwitchListTile(
                title: const Text('Reduce transparency'),
                subtitle: const Text(
                  'Use solid surfaces instead of translucent glass',
                ),
                secondary: const Icon(Icons.opacity_rounded),
                value: prefs.reduceTransparency,
                onChanged: (v) => ref
                    .read(appPreferencesProvider.notifier)
                    .setReduceTransparency(v),
              ),
              const SizedBox(height: Space.s6),

              // 6. Connection
              const SectionHeader(title: 'Connection'),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server'),
                subtitle: Text(serverHost),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => showConnectionSheet(context),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s2,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.error,
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Disconnect'),
                    onPressed: () => _confirmDisconnect(context),
                  ),
                ),
              ),
              const SizedBox(height: Space.s6),

              // 7. About
              const SectionHeader(title: 'About'),
              packageInfoAsync.when(
                data: (info) => ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Sentinel'),
                  subtitle: Text(
                    'Version ${info.version} (build ${info.buildNumber})',
                  ),
                ),
                loading: () => const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Sentinel'),
                  subtitle: Text('Loading…'),
                ),
                error: (err, stack) => const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Sentinel'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
