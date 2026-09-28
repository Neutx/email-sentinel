import 'package:flutter/material.dart';

import '../core/theme/sentinel_colors.dart';

/// Shown for the few milliseconds while the saved connection loads.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Icon(
          Icons.shield_outlined,
          size: 48,
          color: context.colors.primary,
          semanticLabel: 'Sentinel',
        ),
      ),
    );
  }
}
