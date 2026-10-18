import 'package:flutter/material.dart';

/// Provides standardized, strictly monochrome color tokens across the application.
class ArcColors {
  static const background = Color(0xFF0B0B0B);
  static const surfaceToken = Color(0xFF202020);
  static const surfaceVariant = Color(0xFF2A2A2A);
  static const divider = Color(0xFF3A3A3A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB8B8B8);
  static const outlineToken = Color(0xFF707070);
  static const handle = Color(0xFF5A5A5A);
  static const active = Color(0xFFFFFFFF);

  static const sheetRadius = 28.0;
  static const dialogRadius = 28.0;
  static const cardRadius = 20.0;
  static const pillRadius = 999.0;
  static const buttonRadius = 16.0;
  static const screenPadding = 20.0;
  static const minRowHeight = 56.0;
  static const minTouchTarget = 48.0;

  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;

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
