import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/sentinel_colors.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import 'email_tile.dart';

class SwipeableEmailTile extends StatelessWidget {
  const SwipeableEmailTile({
    required this.email,
    required this.onTap,
    required this.onDone,
    required this.onReclassify,
    super.key,
  });

  final EmailItem email;
  final VoidCallback onTap;

  /// Returns true when the email was marked done; the tile only animates out
  /// on success (on failure the controller has already restored it).
  final Future<bool> Function() onDone;
  final Future<void> Function() onReclassify;

  @override
  Widget build(BuildContext context) {
    if (email.isDone) {
      return EmailTile(email: email, onTap: onTap);
    }

    return Dismissible(
      key: ValueKey('email-${email.id}'),
      background: Container(
        decoration: BoxDecoration(
          color: context.sentinelColors.success,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        padding: EdgeInsets.symmetric(horizontal: Space.gutter(context)),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, color: Colors.white),
            const SizedBox(width: Space.s2),
            Text(
              'Done',
              style: context.text.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        padding: EdgeInsets.symmetric(horizontal: Space.gutter(context)),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline_rounded, color: context.colors.onPrimary),
            const SizedBox(width: Space.s2),
            Text(
              'Reclassify',
              style: context.text.labelLarge?.copyWith(
                color: context.colors.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onUpdate: (details) {
        if (details.reached && !details.previousReached) {
          HapticFeedback.lightImpact();
        }
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          return onDone();
        } else if (direction == DismissDirection.endToStart) {
          await onReclassify();
          return false;
        }
        return false;
      },
      child: EmailTile(email: email, onTap: onTap),
    );
  }
}
