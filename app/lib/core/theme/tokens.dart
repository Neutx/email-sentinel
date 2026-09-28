import 'package:flutter/widgets.dart';

/// Spacing scale from docs/design/DESIGN_BRIEF.md §6. Use these, never literals.
abstract final class Space {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;

  /// Horizontal page gutter: 16 on phones, 24 from 600 dp wide.
  static double gutter(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 ? s6 : s4;
}

/// Corner radius roles (DESIGN_BRIEF §6).
abstract final class Radii {
  static const double control = 12;
  static const double card = 16;
  static const double sheet = 28;
  static const double nav = 32;
  static const double chip = 999;
}

/// Motion tokens (DESIGN_BRIEF §7).
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);
  static const Duration stagger = Duration(milliseconds: 30);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// Returns [duration], or zero when the OS asks to disable animations.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Geometry of the floating glass navigation pill (DESIGN_BRIEF §4.1).
abstract final class NavMetrics {
  static const double height = 64;
  static const double bottomGap = 12;
  static const double sideInset = 16;

  /// Bottom padding scrollable content needs so nothing hides behind the pill.
  static double contentBottomPadding(BuildContext context) =>
      height + bottomGap + Space.s4 + MediaQuery.paddingOf(context).bottom;
}
