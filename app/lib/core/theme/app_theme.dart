import 'package:flutter/material.dart';

import 'sentinel_colors.dart';
import 'tokens.dart';

/// Light and dark ThemeData built strictly from DESIGN_BRIEF tokens.
abstract final class AppTheme {
  static const String fontFamily = 'Inter';

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0F766E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFCCFBF1),
    onPrimaryContainer: Color(0xFF042F2E),
    secondary: Color(0xFF0F766E),
    onSecondary: Color(0xFFFFFFFF),
    error: Color(0xFFB91C1C),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFF8FAFC),
    onSurface: Color(0xFF0F172A),
    onSurfaceVariant: Color(0xFF475569),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF1F5F9),
    surfaceContainerHigh: Color(0xFFF1F5F9),
    surfaceContainerHighest: Color(0xFFE2E8F0),
    outline: Color(0xFF94A3B8),
    outlineVariant: Color(0xFFE2E8F0),
    inverseSurface: Color(0xFF0F172A),
    onInverseSurface: Color(0xFFF1F5F9),
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF2DD4BF),
    onPrimary: Color(0xFF042F2E),
    primaryContainer: Color(0xFF134E4A),
    onPrimaryContainer: Color(0xFFCCFBF1),
    secondary: Color(0xFF2DD4BF),
    onSecondary: Color(0xFF042F2E),
    error: Color(0xFFF87171),
    onError: Color(0xFF450A0A),
    surface: Color(0xFF0B1220),
    onSurface: Color(0xFFF1F5F9),
    onSurfaceVariant: Color(0xFFA3B1C6),
    surfaceContainerLowest: Color(0xFF111827),
    surfaceContainerLow: Color(0xFF111827),
    surfaceContainer: Color(0xFF1E293B),
    surfaceContainerHigh: Color(0xFF1E293B),
    surfaceContainerHighest: Color(0xFF253047),
    outline: Color(0xFF64748B),
    outlineVariant: Color(0xFF253047),
    inverseSurface: Color(0xFFF1F5F9),
    onInverseSurface: Color(0xFF0F172A),
  );

  static ThemeData light() => _build(lightScheme, SentinelColors.light);
  static ThemeData dark() => _build(darkScheme, SentinelColors.dark);

  static TextTheme _textTheme(Color ink) {
    const tabular = [FontFeature.tabularFigures()];
    TextStyle s(
      double size,
      double height,
      FontWeight weight, {
      double spacing = 0,
    }) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: spacing,
      color: ink,
    );
    return TextTheme(
      displaySmall: s(32, 40, FontWeight.w600, spacing: -0.2),
      headlineSmall: s(24, 32, FontWeight.w600, spacing: -0.2),
      titleLarge: s(20, 28, FontWeight.w600),
      titleMedium: s(16, 24, FontWeight.w600),
      bodyLarge: s(16, 24, FontWeight.w400),
      bodyMedium: s(14, 20, FontWeight.w400),
      labelLarge: s(14, 20, FontWeight.w500),
      labelMedium: s(12, 16, FontWeight.w500).copyWith(fontFeatures: tabular),
    );
  }

  static ThemeData _build(ColorScheme scheme, SentinelColors colors) {
    final text = _textTheme(scheme.onSurface);
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.card),
      side: BorderSide(color: scheme.outlineVariant),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [colors],
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      chipTheme: ChipThemeData(
        labelStyle: text.labelLarge,
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide.none,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
      // Press feedback = ink ripple only (no lift/elevation changes).
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
