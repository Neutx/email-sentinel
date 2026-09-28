import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    this.width,
    required this.height,
    this.radius = Radii.control,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;

    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }

    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class EmailTileSkeleton extends StatelessWidget {
  const EmailTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 64, height: 20, radius: Radii.chip),
                Spacer(),
                SkeletonBox(width: 48, height: 14, radius: 4),
              ],
            ),
            SizedBox(height: Space.s2),
            SkeletonBox(width: 120, height: 14, radius: 4),
            SizedBox(height: Space.s2),
            SkeletonBox(width: double.infinity, height: 16, radius: 4),
            SizedBox(height: Space.s2),
            SkeletonBox(width: double.infinity, height: 14, radius: 4),
            SizedBox(height: Space.s2),
            SkeletonBox(width: 32, height: 12, radius: 2),
          ],
        ),
      ),
    );
  }
}
