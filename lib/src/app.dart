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

    // Charcoal dark — NOT pure AMOLED black, NOT dynamic colour by default.
    // Default grey premium accent
    const seed = Color(0xFF8E959B);

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
      colorScheme: settings.useDynamicColor
          ? null
          : ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.light,
              surface: const Color(0xFFF9F9F9),
              surfaceContainerLow: const Color(0xFFFFFFFF),
              surfaceContainerHigh: const Color(0xFFF0F0F0),
            ),
      useMaterial3: true,
      appBarStyle: FlexAppBarStyle.surface,
      subThemesData: subThemes,
      textTheme: ArcTypography.textTheme(Brightness.light, family: font),
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 2,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    final dark = FlexThemeData.dark(
      // Layered charcoal: scaffold #121212, surface #181818, container #222222
      colorScheme: settings.useDynamicColor
          ? null
          : ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
      useMaterial3: true,
      appBarStyle: FlexAppBarStyle.surface,
      subThemesData: subThemes,
      textTheme: ArcTypography.textTheme(Brightness.dark, family: font),
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurfaces,
      blendLevel: 2,
      darkIsTrueBlack: false, // Explicitly NOT AMOLED
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
