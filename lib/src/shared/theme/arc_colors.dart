import 'package:flutter/material.dart';

/// Provides standardized, strictly monochrome color tokens across the application.
class ArcColors {
  /// Pure black for light mode primary, white for dark mode primary.
  static Color primary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? Colors.black
          : Colors.white;

  /// Pure white for light mode surface, black for dark mode surface.
  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Colors.black;

  /// Secondary color (subtle grays depending on brightness)
  static Color secondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? Colors.grey.shade800
          : Colors.grey.shade300;

  /// Icon tints and outlines
  static Color outline(BuildContext context) =>
      Theme.of(context).colorScheme.outline;
  static Color outlineVariant(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  /// Text colors
  static Color onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color onSurfaceVariant(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}
