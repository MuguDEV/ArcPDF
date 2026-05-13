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

    // Monochrome theme with pure greyscale. Disable dynamic color for pure monochrome.
    const seed = Colors.grey;

    const subThemes = FlexSubThemesData(
      interactionEffects: true,
      cardRadius: 20,
      inputDecoratorRadius: 16,
      chipRadius: 12,
      navigationBarIndicatorRadius: 18,
      navigationBarBackgroundSchemeColor: SchemeColor.surfaceContainerLow,
      bottomSheetRadius: 24,
    );

    final light = FlexThemeData.light(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.grey.shade800,
        onSecondary: Colors.white,
        surface: const Color(0xFFF9F9F9),
        surfaceContainerLow: const Color(0xFFFFFFFF),
        surfaceContainerHigh: const Color(0xFFE0E0E0),
      ),
      useMaterial3: true,
      appBarStyle: FlexAppBarStyle.surface,
      subThemesData: subThemes,
      textTheme: ArcTypography.textTheme(Brightness.light, family: font),
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 0,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    final dark = FlexThemeData.dark(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.grey.shade300,
        onSecondary: Colors.black,
        surface: const Color(0xFF121212),
        surfaceContainerLow: const Color(0xFF1E1E1E),
        surfaceContainerHigh: const Color(0xFF2C2C2C),
      ),
      useMaterial3: true,
      appBarStyle: FlexAppBarStyle.surface,
      subThemesData: subThemes,
      textTheme: ArcTypography.textTheme(Brightness.dark, family: font),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurfaces,
      blendLevel: 0,
      darkIsTrueBlack: true, // Pure black AMOLED
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
