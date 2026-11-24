import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/navigation/app_shell.dart';
import 'features/security/lock_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'dart:async';
import 'dart:io';

import 'features/settings/settings_controller.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'features/pdf/data/ocr_module_controller.dart';

import 'features/sharing/intent_service.dart';
import 'theme/arc_typography.dart';
import 'features/pdf/viewer/route_observer.dart';
import 'shared/theme/arc_theme.dart';
import 'core/utils/app_diagnostics.dart';
import 'core/utils/logger.dart';
import 'core/platform/android_job_service.dart';
import 'package:path/path.dart' as p;

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

    // Request the OCR module in the background once onboarding is done. This
    // runs after the first frame and is never awaited by startup.
    ref.listenManual<bool>(onboardingCompletedProvider, (previous, next) {
      if (next) _requestBackgroundOcr();
    });
    // Turning OCR or background download on later also requests the module.
    ref.listenManual<AppSettings>(settingsControllerProvider,
        (previous, next) {
      if (previous == null || !ref.read(onboardingCompletedProvider)) return;
      final enabledNow = (next.enableOcr && !previous.enableOcr) ||
          (next.ocrBackgroundDownload && !previous.ocrBackgroundDownload);
      if (enabledNow) _requestBackgroundOcr();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(onboardingCompletedProvider)) {
        _requestBackgroundOcr();
      }
    });

    // Apply initial refresh rate safely outside of build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid) {
        try {
          final interrupted = await AndroidJobService.recover();
          if (interrupted != null) {
            final outputPath = interrupted.outputPath;
            if (outputPath != null) {
              final parent = Directory(p.dirname(outputPath));
              if (await parent.exists()) {
                await for (final entry in parent.list(followLinks: false)) {
                  if (entry is Directory &&
                      p.basename(entry.path).startsWith('.arcpdf_')) {
                    await entry.delete(recursive: true);
                  }
                }
              }
            }
            await AndroidJobService.finish();
            await AppLogger.warning(
              'Recovered an interrupted ${interrupted.title} job; temporary output was cleaned up',
            );
            final context =
                ref.read(intentServiceProvider).navigatorKey.currentContext;
            if (context != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${interrupted.title} was interrupted. No partial output was kept.',
                  ),
                ),
              );
            }
          }
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

  void _requestBackgroundOcr() {
    final settings = ref.read(settingsControllerProvider);
    if (!settings.enableOcr || !settings.ocrBackgroundDownload) return;
    unawaited(() async {
      try {
        await ref
            .read(ocrModuleControllerProvider.notifier)
            .requestBackgroundInstallIfAllowed();
      } catch (_) {
        // OCR is optional. Never let it affect startup.
      }
    }());
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
      Animate.defaultDuration = (180 * settings.animationSpeed).ms;
    }

    final themes = _themesFor(font, settings.accent, settings.highContrast);

    // Android-native scrolling is more predictable and avoids the elastic
    // movement fighting document/card gestures on older devices.
    final scrollBehavior = const MaterialScrollBehavior().copyWith(
      physics:
          const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
