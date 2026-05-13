import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/navigation/app_shell.dart';
import 'features/settings/settings_controller.dart';
import 'theme/arc_typography.dart';

class ArcPdfApp extends ConsumerWidget {
  const ArcPdfApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final font = settings.fontFamily;

    // Softened greyscale theme based on user request.
    const seed = Color(0xFF757575);

    const subThemes = FlexSubThemesData(
      interactionEffects: true,
      cardRadius: 28,
      inputDecoratorRadius: 28,
      chipRadius: 50,
      navigationBarIndicatorRadius: 28,
      navigationBarBackgroundSchemeColor: SchemeColor.surfaceContainerLow,
      bottomSheetRadius: 28,
      dialogRadius: 28,
      buttonMinSize: Size(64, 48),
      thickBorderWidth: 2.0,
      thinBorderWidth: 1.0,
    );

    final light = FlexThemeData.light(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        primary: const Color(0xFF303030),
        onPrimary: const Color(0xFFFFFFFF),
        secondary: const Color(0xFF606060),
        onSecondary: const Color(0xFFFFFFFF),
        surface: const Color(0xFFF5F5F5),
        surfaceContainerLow: const Color(0xFFFFFFFF),
        surfaceContainerHigh: const Color(0xFFEBEBEB),
      ),
      useMaterial3: true,
      appBarStyle: FlexAppBarStyle.surface,
      subThemesData: subThemes,
      textTheme: ArcTypography.textTheme(Brightness.light, family: font),
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 2, // Slight blend for softer look
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    final dark = FlexThemeData.dark(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        primary: const Color(0xFFE0E0E0),
        onPrimary: const Color(0xFF1E1E1E),
        secondary: const Color(0xFFA0A0A0),
        onSecondary: const Color(0xFF1E1E1E),
        surface: const Color(0xFF121212), // Soft dark instead of pure black
        surfaceContainerLow: const Color(0xFF1E1E1E),
        surfaceContainerHigh: const Color(0xFF2C2C2C),
      ),
      useMaterial3: true,
      appBarStyle: FlexAppBarStyle.surface,
      subThemesData: subThemes,
      textTheme: ArcTypography.textTheme(Brightness.dark, family: font),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurfaces,
      blendLevel: 2, // Slight blend
      darkIsTrueBlack: false, // Turned off pure black
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    return MaterialApp(
      title: 'ArcPDF',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: light,
      darkTheme: dark,
      home: const AppShell(),
    );
  }
}
