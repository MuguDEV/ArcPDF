import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/navigation/app_shell.dart';
import 'features/security/lock_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'dart:io';

import 'features/settings/settings_controller.dart';

import 'features/sharing/intent_service.dart';
import 'theme/arc_typography.dart';
import 'features/pdf/viewer/route_observer.dart';
import 'shared/theme/arc_theme.dart';
import 'core/utils/app_diagnostics.dart';

class ArcPdfApp extends ConsumerStatefulWidget {
  const ArcPdfApp({super.key});

  @override
  ConsumerState<ArcPdfApp> createState() => _ArcPdfAppState();
}

class _ArcPdfAppState extends ConsumerState<ArcPdfApp> {
  final _logNavigatorObserver = AppLogNavigatorObserver();
  ({
    AppFontFamily font,
    ArcAccent accent,
    HighContrastMode contrast
  })? _themeKey;
  ArcThemeSet? _themes;

  /// Themes only change with font, accent or contrast, not with every
  /// slider tick in Settings.
  ArcThemeSet _themesFor(
    AppFontFamily font,
    ArcAccent accent,
    HighContrastMode contrast,
  ) {
    final key = (font: font, accent: accent, contrast: contrast);
    final cached = _themes;
    if (cached != null && _themeKey == key) return cached;
    _themeKey = key;
    return _themes = buildArcThemeSet(
      accent: accent,
      contrast: contrast,
      textTheme: (brightness) =>
          ArcTypography.textTheme(brightness, family: font),
    );
  }

  @override
  void initState() {
    super.initState();
    ref.read(intentServiceProvider).init();

    // Apply initial refresh rate safely outside of build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid) {
        try {
          final settings = ref.read(settingsControllerProvider);
          if (settings.lowPowerMode) {
            await FlutterDisplayMode.setLowRefreshRate();
          } else {
            await FlutterDisplayMode.setHighRefreshRate();
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    ref.read(intentServiceProvider).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final font = settings.fontFamily;

    // Listen to changes to set refresh rate safely (not every build frame)
    ref.listen<AppSettings>(settingsControllerProvider, (prev, next) async {
      if (prev?.lowPowerMode != next.lowPowerMode && Platform.isAndroid) {
        try {
          if (next.lowPowerMode) {
            await FlutterDisplayMode.setLowRefreshRate();
          } else {
            await FlutterDisplayMode.setHighRefreshRate();
          }
        } catch (_) {}
      }
    });

    // Apply low power mode to global animations
    if (settings.lowPowerMode) {
      Animate.defaultDuration = 0.ms;
    } else {
      Animate.defaultDuration = (300 * settings.animationSpeed).ms;
    }

    final themes = _themesFor(font, settings.accent, settings.highContrast);

    // Create a global scroll behavior to enforce bouncing everywhere
    final scrollBehavior = const MaterialScrollBehavior().copyWith(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      scrollbars: false,
      overscroll: false,
    );

    return MaterialApp(
      title: 'ArcPDF',
      navigatorKey: ref.read(intentServiceProvider).navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: themes.light,
      darkTheme: themes.dark,
      highContrastTheme: themes.highContrastLight,
      highContrastDarkTheme: themes.highContrastDark,
      scrollBehavior: scrollBehavior,
      navigatorObservers: [pdfRouteObserver, _logNavigatorObserver],
      home: const AppShell(),
      builder: (context, child) =>
          LockScreenWrapper(child: child ?? const SizedBox.shrink()),
    );
  }
}
