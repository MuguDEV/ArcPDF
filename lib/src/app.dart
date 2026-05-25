import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/navigation/app_shell.dart';
import 'features/security/lock_screen.dart';
import 'features/settings/settings_controller.dart';
import 'features/sharing/intent_service.dart';
import 'theme/arc_typography.dart';

class ArcPdfApp extends ConsumerStatefulWidget {
  const ArcPdfApp({super.key});

  @override
  ConsumerState<ArcPdfApp> createState() => _ArcPdfAppState();
}

class _ArcPdfAppState extends ConsumerState<ArcPdfApp> {
  @override
  void initState() {
    super.initState();
    ref.read(intentServiceProvider).init();
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

    const lightColorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF303030),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE0E0E0),
      onPrimaryContainer: Color(0xFF1E1E1E),
      secondary: Color(0xFF606060),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFEBEBEB),
      onSecondaryContainer: Color(0xFF1E1E1E),
      tertiary: Color(0xFF757575),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFEEEEEE),
      onTertiaryContainer: Color(0xFF1E1E1E),
      error: Color(0xFF424242),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFE0E0E0),
      onErrorContainer: Color(0xFF1E1E1E),
      surface: Color(0xFFF5F5F5),
      onSurface: Color(0xFF1E1E1E),
      surfaceContainerHighest: Color(0xFFD4D4D4),
      surfaceContainerHigh: Color(0xFFEBEBEB),
      surfaceContainer: Color(0xFFF0F0F0),
      surfaceContainerLow: Color(0xFFFFFFFF),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      onSurfaceVariant: Color(0xFF424242),
      outline: Color(0xFF9E9E9E),
      outlineVariant: Color(0xFFE0E0E0),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF303030),
      onInverseSurface: Color(0xFFF5F5F5),
      inversePrimary: Color(0xFFE0E0E0),
      surfaceTint: Colors.transparent,
    );

    const darkColorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFE0E0E0),
      onPrimary: Color(0xFF1E1E1E),
      primaryContainer: Color(0xFF424242),
      onPrimaryContainer: Color(0xFFFFFFFF),
      secondary: Color(0xFFA0A0A0),
      onSecondary: Color(0xFF1E1E1E),
      secondaryContainer: Color(0xFF303030),
      onSecondaryContainer: Color(0xFFFFFFFF),
      tertiary: Color(0xFF9E9E9E),
      onTertiary: Color(0xFF1E1E1E),
      tertiaryContainer: Color(0xFF424242),
      onTertiaryContainer: Color(0xFFFFFFFF),
      error: Color(0xFFBDBDBD),
      onError: Color(0xFF1E1E1E),
      errorContainer: Color(0xFF424242),
      onErrorContainer: Color(0xFFFFFFFF),
      surface: Color(0xFF121212),
      onSurface: Color(0xFFE0E0E0),
      surfaceContainerHighest: Color(0xFF383838),
      surfaceContainerHigh: Color(0xFF2C2C2C),
      surfaceContainer: Color(0xFF242424),
      surfaceContainerLow: Color(0xFF1E1E1E),
      surfaceContainerLowest: Color(0xFF0F0F0F),
      onSurfaceVariant: Color(0xFFBDBDBD),
      outline: Color(0xFF757575),
      outlineVariant: Color(0xFF424242),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE0E0E0),
      onInverseSurface: Color(0xFF1E1E1E),
      inversePrimary: Color(0xFF303030),
      surfaceTint: Colors.transparent,
    );

    ThemeData buildTheme(ColorScheme colorScheme, Brightness brightness) {
      final textTheme = ArcTypography.textTheme(brightness, family: font);

      return ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        brightness: brightness,
        textTheme: textTheme,
        scaffoldBackgroundColor: colorScheme.surface,
        splashColor: brightness == Brightness.light ? Colors.black12 : Colors.white12,
        highlightColor: brightness == Brightness.light ? Colors.black12 : Colors.white12,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          clipBehavior: Clip.antiAlias,
          color: colorScheme.surfaceContainerLow,
          elevation: 0,
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: colorScheme.surfaceContainerHigh,
          elevation: 0,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          elevation: 0,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          side: BorderSide.none,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(width: 1.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(width: 1.0, color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(width: 2.0, color: colorScheme.primary),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(width: 1.0, color: colorScheme.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(width: 2.0, color: colorScheme.error),
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: colorScheme.surfaceContainerLow,
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(64, 48),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 48),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 48),
            side: BorderSide(width: 1.0, color: colorScheme.outline),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 48),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'ArcPDF',
      navigatorKey: ref.read(intentServiceProvider).navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(lightColorScheme, Brightness.light),
      darkTheme: buildTheme(darkColorScheme, Brightness.dark),
      home: const AppShell(),
      builder: (context, child) => LockScreenWrapper(child: child ?? const SizedBox.shrink()),
    );
  }
}
