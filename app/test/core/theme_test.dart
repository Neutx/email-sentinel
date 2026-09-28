import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/theme/app_theme.dart';
import 'package:sentinel/core/theme/sentinel_colors.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    group('$name theme meets WCAG AA', () {
      final s = theme.colorScheme;
      final c = theme.extension<SentinelColors>()!;

      test('text on backgrounds', () {
        expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onSurface, c.card), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onSurfaceVariant, c.card), greaterThanOrEqualTo(4.5));
        expect(
          contrast(s.onSurfaceVariant, s.surfaceContainerHigh),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(s.primary, c.card), greaterThanOrEqualTo(4.5));
      });

      test('category and semantic colors on cards', () {
        for (final color in [
          c.urgent,
          c.project,
          c.transactional,
          c.fyi,
          c.marketing,
          c.spam,
          c.caution,
          c.success,
          s.error,
        ]) {
          expect(contrast(color, c.card), greaterThanOrEqualTo(4.5));
        }
      });

      test('uses the bundled Inter font', () {
        expect(theme.textTheme.bodyLarge?.fontFamily, 'Inter');
      });
    });
  }
}
