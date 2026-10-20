import 'package:flutter/material.dart';

/// Optional single accent colour. [none] keeps the app strictly monochrome.
///
/// Accents are muted and are only applied to primary / selected / indicator
/// roles. Every accent has a light-theme and a dark-theme variant that keeps
/// at least 4.5:1 contrast against the monochrome surfaces.
enum ArcAccent { none, slate, sage, clay, plum, teal }

extension ArcAccentX on ArcAccent {
  String get displayName => switch (this) {
        ArcAccent.none => 'None',
        ArcAccent.slate => 'Slate',
        ArcAccent.sage => 'Sage',
        ArcAccent.clay => 'Clay',
        ArcAccent.plum => 'Plum',
        ArcAccent.teal => 'Teal',
      };

  /// Accent colour for [brightness], or null for [ArcAccent.none].
  Color? colorFor(Brightness brightness) {
    final light = brightness == Brightness.light;
    return switch (this) {
      ArcAccent.none => null,
      ArcAccent.slate =>
        light ? const Color(0xFF2F5D8A) : const Color(0xFF8FB4E0),
      ArcAccent.sage =>
        light ? const Color(0xFF3A6B4F) : const Color(0xFF8CC4A0),
      ArcAccent.clay =>
        light ? const Color(0xFF8A4B2D) : const Color(0xFFE0A07C),
      ArcAccent.plum =>
        light ? const Color(0xFF6B3F6B) : const Color(0xFFD0A0D0),
      ArcAccent.teal =>
        light ? const Color(0xFF1F6B6B) : const Color(0xFF7CC4C4),
    };
  }
}

/// WCAG contrast ratio between two opaque colours.
double arcContrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Black or white, whichever reads best on top of [background].
Color arcOnColor(Color background) =>
    arcContrastRatio(background, Colors.white) >=
            arcContrastRatio(background, Colors.black)
        ? Colors.white
        : Colors.black;
