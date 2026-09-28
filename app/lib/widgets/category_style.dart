import 'package:flutter/material.dart';

import '../core/theme/sentinel_colors.dart';
import '../data/models.dart';

class CategoryStyle {
  const CategoryStyle({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  static CategoryStyle of(BuildContext context, EmailCategory c) {
    final colors = context.sentinelColors;
    return switch (c) {
      EmailCategory.urgentActionable => CategoryStyle(
        color: colors.urgent,
        icon: Icons.priority_high_rounded,
        label: c.label,
      ),
      EmailCategory.projectUpdate => CategoryStyle(
        color: colors.project,
        icon: Icons.account_tree_rounded,
        label: c.label,
      ),
      EmailCategory.transactional => CategoryStyle(
        color: colors.transactional,
        icon: Icons.receipt_long_rounded,
        label: c.label,
      ),
      EmailCategory.generalFyi => CategoryStyle(
        color: colors.fyi,
        icon: Icons.info_outline_rounded,
        label: c.label,
      ),
      EmailCategory.marketingPromo => CategoryStyle(
        color: colors.marketing,
        icon: Icons.campaign_outlined,
        label: c.label,
      ),
      EmailCategory.spam => CategoryStyle(
        color: colors.spam,
        icon: Icons.report_gmailerrorred_rounded,
        label: c.label,
      ),
    };
  }
}
