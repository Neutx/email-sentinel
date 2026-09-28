import 'package:flutter/material.dart';

/// Brand + semantic colors that Material's ColorScheme has no slot for.
/// Values are copied verbatim from docs/design/DESIGN_BRIEF.md §3–§4.
@immutable
class SentinelColors extends ThemeExtension<SentinelColors> {
  const SentinelColors({
    required this.card,
    required this.caution,
    required this.success,
    required this.urgent,
    required this.project,
    required this.transactional,
    required this.fyi,
    required this.marketing,
    required this.spam,
    required this.glassFill,
    required this.glassEdge,
    required this.glassHighlight,
    required this.glassShadow,
    required this.glassSolid,
  });

  final Color card;
  final Color caution;
  final Color success;
  final Color urgent;
  final Color project;
  final Color transactional;
  final Color fyi;
  final Color marketing;
  final Color spam;
  final Color glassFill;
  final Color glassEdge;
  final Color glassHighlight;
  final Color glassShadow;
  final Color glassSolid;

  static const SentinelColors light = SentinelColors(
    card: Color(0xFFFFFFFF),
    caution: Color(0xFFC2410C),
    success: Color(0xFF15803D),
    urgent: Color(0xFFB91C1C),
    project: Color(0xFF1D4ED8),
    transactional: Color(0xFFB45309),
    fyi: Color(0xFF475569),
    marketing: Color(0xFF7E22CE),
    spam: Color(0xFF57534E),
    glassFill: Color(0xB8FFFFFF), // #FFFFFF @ 0.72
    glassEdge: Color(0x8CFFFFFF), // #FFFFFF @ 0.55
    glassHighlight: Color(0x99FFFFFF), // #FFFFFF @ 0.60
    glassShadow: Color(0x1A0F172A), // #0F172A @ 0.10
    glassSolid: Color(0xFFFFFFFF),
  );

  static const SentinelColors dark = SentinelColors(
    card: Color(0xFF111827),
    caution: Color(0xFFFB923C),
    success: Color(0xFF4ADE80),
    urgent: Color(0xFFF87171),
    project: Color(0xFF60A5FA),
    transactional: Color(0xFFFBBF24),
    fyi: Color(0xFF94A3B8),
    marketing: Color(0xFFC084FC),
    spam: Color(0xFFA8A29E),
    glassFill: Color(0xC7111827), // #111827 @ 0.78
    glassEdge: Color(0x1AFFFFFF), // #FFFFFF @ 0.10
    glassHighlight: Color(0x14FFFFFF), // #FFFFFF @ 0.08
    glassShadow: Color(0x73000000), // #000000 @ 0.45
    glassSolid: Color(0xFF172033),
  );

  @override
  SentinelColors copyWith({
    Color? card,
    Color? caution,
    Color? success,
    Color? urgent,
    Color? project,
    Color? transactional,
    Color? fyi,
    Color? marketing,
    Color? spam,
    Color? glassFill,
    Color? glassEdge,
    Color? glassHighlight,
    Color? glassShadow,
    Color? glassSolid,
  }) {
    return SentinelColors(
      card: card ?? this.card,
      caution: caution ?? this.caution,
      success: success ?? this.success,
      urgent: urgent ?? this.urgent,
      project: project ?? this.project,
      transactional: transactional ?? this.transactional,
      fyi: fyi ?? this.fyi,
      marketing: marketing ?? this.marketing,
      spam: spam ?? this.spam,
      glassFill: glassFill ?? this.glassFill,
      glassEdge: glassEdge ?? this.glassEdge,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      glassShadow: glassShadow ?? this.glassShadow,
      glassSolid: glassSolid ?? this.glassSolid,
    );
  }

  @override
  SentinelColors lerp(ThemeExtension<SentinelColors>? other, double t) {
    if (other is! SentinelColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SentinelColors(
      card: l(card, other.card),
      caution: l(caution, other.caution),
      success: l(success, other.success),
      urgent: l(urgent, other.urgent),
      project: l(project, other.project),
      transactional: l(transactional, other.transactional),
      fyi: l(fyi, other.fyi),
      marketing: l(marketing, other.marketing),
      spam: l(spam, other.spam),
      glassFill: l(glassFill, other.glassFill),
      glassEdge: l(glassEdge, other.glassEdge),
      glassHighlight: l(glassHighlight, other.glassHighlight),
      glassShadow: l(glassShadow, other.glassShadow),
      glassSolid: l(glassSolid, other.glassSolid),
    );
  }
}

extension SentinelThemeX on BuildContext {
  SentinelColors get sentinelColors =>
      Theme.of(this).extension<SentinelColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
