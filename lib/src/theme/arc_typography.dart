import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/settings/settings_controller.dart';

abstract final class ArcTypography {
  static TextTheme textTheme(
    Brightness brightness, {
    AppFontFamily family = AppFontFamily.inter,
  }) {
    final base = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;
    final themed = _applyGoogleFont(base, family);
    TextStyle role(TextStyle? style, double size, FontWeight weight,
            {double height = 1.4, double tracking = 0}) =>
        (style ?? const TextStyle()).copyWith(
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: tracking,
        );
    return themed.copyWith(
      titleLarge: themed.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.25,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.35,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.5,
      ),
      bodyMedium: themed.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.45,
      ),
      bodySmall: themed.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.4,
      ),
      displayLarge: role(themed.displayLarge, 48, FontWeight.w700,
          height: 1.15, tracking: -1),
      displayMedium: role(themed.displayMedium, 40, FontWeight.w700,
          height: 1.15, tracking: -0.8),
      displaySmall: role(themed.displaySmall, 32, FontWeight.w700,
          height: 1.2, tracking: -0.6),
      headlineLarge: role(themed.headlineLarge, 28, FontWeight.w600,
          height: 1.25, tracking: -0.5),
      headlineMedium: role(themed.headlineMedium, 24, FontWeight.w600,
          height: 1.3, tracking: -0.4),
      headlineSmall: role(themed.headlineSmall, 22, FontWeight.w600,
          height: 1.3, tracking: -0.3),
      titleSmall: role(themed.titleSmall, 14, FontWeight.w600),
      labelLarge: role(themed.labelLarge, 14, FontWeight.w600),
      labelMedium: role(themed.labelMedium, 12, FontWeight.w500),
      labelSmall: role(themed.labelSmall, 12, FontWeight.w500),
    );
  }

  static TextTheme _applyGoogleFont(TextTheme base, AppFontFamily family) {
    try {
      return switch (family) {
        AppFontFamily.system => base,
        AppFontFamily.inter => GoogleFonts.interTextTheme(base),
        AppFontFamily.roboto => GoogleFonts.robotoTextTheme(base),
        AppFontFamily.plusJakarta => GoogleFonts.plusJakartaSansTextTheme(base),
        AppFontFamily.nunito => GoogleFonts.nunitoTextTheme(base),
      };
    } catch (_) {
      return base;
    }
  }
}
