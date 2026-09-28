import 'package:flutter/material.dart';

import '../core/theme/sentinel_colors.dart';
import '../core/theme/tokens.dart';

enum _BannerKind { offline, dryRun, scanRunning }

class StatusBanner extends StatelessWidget {
  const StatusBanner.offline({required this.onRetry, super.key})
    : _kind = _BannerKind.offline;

  const StatusBanner.dryRun({super.key})
    : _kind = _BannerKind.dryRun,
      onRetry = null;

  const StatusBanner.scanRunning({super.key})
    : _kind = _BannerKind.scanRunning,
      onRetry = null;

  final _BannerKind _kind;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Color tintColor;
    final IconData icon;
    final String text;

    switch (_kind) {
      case _BannerKind.offline:
        tintColor = context.colors.error;
        icon = Icons.cloud_off_rounded;
        text = "Offline — can't reach Sentinel";
      case _BannerKind.dryRun:
        tintColor = context.sentinelColors.caution;
        icon = Icons.science_outlined;
        text = 'Dry run — nothing is really trashed or unsubscribed';
      case _BannerKind.scanRunning:
        tintColor = context.colors.primary;
        icon = Icons.sync_rounded;
        text = 'Scanning inbox…';
    }

    return Container(
      width: double.infinity,
      color: tintColor.withValues(alpha: 0.12),
      padding: EdgeInsets.symmetric(
        horizontal: Space.gutter(context),
        vertical: Space.s2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: tintColor),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Text(
                  text,
                  style: context.text.labelLarge?.copyWith(color: tintColor),
                ),
              ),
              if (_kind == _BannerKind.offline && onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: tintColor,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Retry'),
                ),
            ],
          ),
          if (_kind == _BannerKind.scanRunning) ...[
            const SizedBox(height: Space.s1),
            LinearProgressIndicator(
              color: tintColor,
              backgroundColor: tintColor.withValues(alpha: 0.2),
            ),
          ],
        ],
      ),
    );
  }
}
