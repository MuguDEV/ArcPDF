import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/settings/settings_controller.dart';

abstract final class ArcTypography {
  static TextTheme textTheme(Brightness brightness, {AppFontFamily family = AppFontFamily.inter}) {
    final base = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;
    final themed = _applyGoogleFont(base, family);
    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
      displaySmall: themed.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineLarge: themed.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineMedium: themed.headlineMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
      titleLarge: themed.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: themed.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      bodyLarge: themed.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: themed.bodyMedium?.copyWith(height: 1.45),
      labelLarge: themed.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
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
      // Network/cache miss — fall back to system font
      return base;
    }
  }
}
