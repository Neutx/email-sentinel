import 'package:flutter/material.dart';

// Placeholder entry point. Hermes replaces this in Phase 1 of
// docs/plans/2026-09-28-sentinel-mobile-plan.md.
void main() {
  runApp(const SentinelApp());
}

class SentinelApp extends StatelessWidget {
  const SentinelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Sentinel',
      home: Scaffold(body: Center(child: Text('Sentinel'))),
    );
  }
}
