import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/app_preferences.dart';
import 'sentinel_colors.dart';

/// Liquid Glass "Regular" tier (DESIGN_BRIEF §4). Navigation layer ONLY:
/// the floating nav pill and the collapsed top app bar. Never use inside
/// list items, cards, sheets or anything that scrolls.
class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.showShadow = true,
  });

  static const double blurSigma = 20;

  final Widget child;
  final BorderRadius borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.sentinelColors;
    final solid =
        ref.watch(reduceTransparencyProvider) ||
        MediaQuery.highContrastOf(context);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? colors.glassSolid : colors.glassFill,
        borderRadius: borderRadius,
        border: Border.all(color: colors.glassEdge),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: solid
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.4],
                  colors: [
                    colors.glassHighlight,
                    colors.glassHighlight.withValues(alpha: 0),
                  ],
                ),
        ),
        child: child,
      ),
    );

    if (!solid) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      );
    }

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: colors.glassShadow,
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(borderRadius: borderRadius, child: surface),
      ),
    );
  }
}
