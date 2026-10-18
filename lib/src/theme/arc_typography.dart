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
    return themed.copyWith(
      titleLarge: themed.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),
      bodyMedium: themed.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),
      bodySmall: themed.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),
      displayLarge: themed.displayLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
      displaySmall: themed.displaySmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineLarge: themed.headlineLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineMedium: themed.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
      labelLarge: themed.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      ),
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
