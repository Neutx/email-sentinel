import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../core/theme/glass.dart';
import '../core/theme/sentinel_colors.dart';
import '../core/theme/tokens.dart';

/// Standard tab page: large title that collapses into a glass top bar
/// (DESIGN_BRIEF §4.2), optional pull-to-refresh, and bottom padding that
/// clears the floating nav pill.
class TabScaffold extends StatelessWidget {
  const TabScaffold({
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.onRefresh,
    super.key,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          toolbarHeight: 64,
          expandedHeight: 128,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: [
            ...actions,
            const SizedBox(width: Space.s2),
          ],
          flexibleSpace: _CollapsingGlassTitle(title: title),
        ),
        ...slivers,
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: NavMetrics.contentBottomPadding(context),
          ),
        ),
      ],
    );
    return Scaffold(
      body: onRefresh == null
          ? scroll
          : RefreshIndicator(
              onRefresh: onRefresh!,
              edgeOffset: 128,
              child: scroll,
            ),
    );
  }
}

class _CollapsingGlassTitle extends StatelessWidget {
  const _CollapsingGlassTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final range = settings == null
        ? 0.0
        : settings.maxExtent - settings.minExtent;
    // 0 = fully expanded, 1 = fully collapsed.
    final t = range <= 0
        ? 1.0
        : ((settings!.maxExtent - settings.currentExtent) / range).clamp(
            0.0,
            1.0,
          );
    final text = context.text;
    final gutter = Space.gutter(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: t > 0.95 ? 1 : 0,
          duration: Motion.of(context, Motion.fast),
          child: const GlassSurface(
            showShadow: false,
            child: SizedBox.expand(),
          ),
        ),
        Positioned(
          left: gutter,
          right: gutter + 96,
          bottom: lerpDouble(Space.s4, Space.s5, t),
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle.lerp(text.headlineSmall, text.titleLarge, t),
            ),
          ),
        ),
      ],
    );
  }
}
