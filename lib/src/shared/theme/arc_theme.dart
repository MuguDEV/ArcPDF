import 'package:flutter/material.dart';

import '../utils/traced_page_transitions_builder.dart';
import 'arc_accent.dart';
import 'arc_colors.dart';
import 'arc_control_theme.dart';

/// Marker carried by the app theme so custom widgets (blurred bars, glass
/// surfaces) can switch to opaque, outlined rendering in high contrast.
@immutable
class ArcContrast extends ThemeExtension<ArcContrast> {
  const ArcContrast({this.highContrast = false});

  final bool highContrast;

  /// Whether the surrounding theme is the high-contrast variant.
  static bool isHigh(BuildContext context) =>
      Theme.of(context).extension<ArcContrast>()?.highContrast ?? false;

  @override
  ArcContrast copyWith({bool? highContrast}) =>
      ArcContrast(highContrast: highContrast ?? this.highContrast);

  @override
  ArcContrast lerp(ThemeExtension<ArcContrast>? other, double t) =>
      other is ArcContrast && t >= 0.5 ? other : this;
}

/// Light and dark themes in normal and high-contrast flavours.
@immutable
class ArcThemeSet {
  const ArcThemeSet({
    required this.light,
    required this.dark,
    required this.highContrastLight,
    required this.highContrastDark,
  });

  final ThemeData light;
  final ThemeData dark;
  final ThemeData highContrastLight;
  final ThemeData highContrastDark;
}

/// Builds the four app themes for a settings combination.
///
/// The mapping onto [MaterialApp] works with its own `MediaQuery.highContrast`
/// handling: when the mode is [HighContrastMode.off] the high-contrast slots
/// reuse the normal themes, when [HighContrastMode.on] the normal slots hold
/// the high-contrast themes, and when [HighContrastMode.system] each slot
/// holds its natural theme.
ArcThemeSet buildArcThemeSet({
  required TextTheme Function(Brightness brightness) textTheme,
  ArcAccent accent = ArcAccent.none,
  HighContrastMode contrast = HighContrastMode.system,
}) {
  ThemeData normal(Brightness b) =>
      buildArcTheme(brightness: b, textTheme: textTheme(b), accent: accent);
  ThemeData high(Brightness b) =>
      buildArcTheme(brightness: b, textTheme: textTheme(b), highContrast: true);

  switch (contrast) {
    case HighContrastMode.off:
      final light = normal(Brightness.light);
      final dark = normal(Brightness.dark);
      return ArcThemeSet(
        light: light,
        dark: dark,
        highContrastLight: light,
        highContrastDark: dark,
      );
    case HighContrastMode.on:
      final light = high(Brightness.light);
      final dark = high(Brightness.dark);
      return ArcThemeSet(
        light: light,
        dark: dark,
        highContrastLight: light,
        highContrastDark: dark,
      );
    case HighContrastMode.system:
      return ArcThemeSet(
        light: normal(Brightness.light),
        dark: normal(Brightness.dark),
        highContrastLight: high(Brightness.light),
        highContrastDark: high(Brightness.dark),
      );
  }
}

/// How the app decides to use the high-contrast theme.
enum HighContrastMode { off, system, on }

extension HighContrastModeX on HighContrastMode {
  String get displayName => switch (this) {
        HighContrastMode.off => 'Off',
        HighContrastMode.system => 'Follow system',
        HighContrastMode.on => 'On',
      };
}

const _lightScheme = ColorScheme(
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
  surface: Color(0xFFECECEC),
  onSurface: Color(0xFF171717),
  surfaceContainerHighest: Color(0xFFD0D0D0),
  surfaceContainerHigh: Color(0xFFE0E0E0),
  surfaceContainer: Color(0xFFE6E6E6),
  surfaceContainerLow: Color(0xFFF7F7F7),
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

const _darkScheme = ColorScheme(
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

/// Pure black/white surfaces and text, solid outlines. No accent colours.
ColorScheme _highContrastScheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final bg = light ? Colors.white : Colors.black;
  final fg = light ? Colors.black : Colors.white;
  return ColorScheme(
    brightness: brightness,
    primary: fg,
    onPrimary: bg,
    primaryContainer: bg,
    onPrimaryContainer: fg,
    secondary: fg,
    onSecondary: bg,
    secondaryContainer: bg,
    onSecondaryContainer: fg,
    tertiary: fg,
    onTertiary: bg,
    tertiaryContainer: bg,
    onTertiaryContainer: fg,
    error: fg,
    onError: bg,
    errorContainer: bg,
    onErrorContainer: fg,
    surface: bg,
    onSurface: fg,
    surfaceContainerHighest: bg,
    surfaceContainerHigh: bg,
    surfaceContainer: bg,
    surfaceContainerLow: bg,
    surfaceContainerLowest: bg,
    onSurfaceVariant: fg,
    outline: fg,
    outlineVariant: fg,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: fg,
    onInverseSurface: bg,
    inversePrimary: fg,
    surfaceTint: Colors.transparent,
  );
}

/// Minimum contrast an accent must keep against the monochrome surface; below
/// this the accent is ignored and the pure monochrome primary is used.
const arcAccentMinContrast = 4.5;

/// Builds the app [ThemeData].
///
/// Surfaces stay monochrome. [accent] only recolours primary / selected /
/// indicator roles. In [highContrast] the accent is ignored, surfaces are pure
/// black/white, outlines are heavier and bars are opaque.
ThemeData buildArcTheme({
  required Brightness brightness,
  required TextTheme textTheme,
  ArcAccent accent = ArcAccent.none,
  bool highContrast = false,
}) {
  final isLight = brightness == Brightness.light;
  final base = isLight ? _lightScheme : _darkScheme;

  late final ColorScheme colorScheme;
  Color? accentColor;
  if (highContrast) {
    colorScheme = _highContrastScheme(brightness);
  } else {
    var primary = isLight ? Colors.black : Colors.white;
    var onPrimary = isLight ? Colors.white : Colors.black;
    final candidate = accent.colorFor(brightness);
    if (candidate != null &&
        arcContrastRatio(candidate, base.surface) >= arcAccentMinContrast) {
      accentColor = candidate;
      primary = candidate;
      onPrimary = arcOnColor(candidate);
    }
    colorScheme = base.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      secondary: isLight ? Colors.grey.shade800 : Colors.grey.shade300,
    );
  }

  final outlineWidth = highContrast ? 2.0 : 1.0;
  final outlineSide = BorderSide(color: colorScheme.outline, width: 2);
  final text = highContrast
      ? textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        )
      : textTheme;
  RoundedRectangleBorder rounded(double radius, {BorderSide? side}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: side ?? BorderSide.none,
      );
  final buttonShape = rounded(ArcColors.buttonRadius);
  final hcButtonShape = rounded(ArcColors.buttonRadius, side: outlineSide);

  var theme = applyArcControlTheme(ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    textTheme: text,
    scaffoldBackgroundColor: colorScheme.surface,
    splashColor: isLight ? Colors.black12 : Colors.white12,
    highlightColor: isLight ? Colors.black12 : Colors.white12,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: TracedZoomPageTransitionsBuilder(
        allowEnterRouteSnapshotting: true,
      )
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: highContrast
          ? Border(bottom: BorderSide(color: colorScheme.outline, width: 2))
          : null,
    ),
    cardTheme: CardThemeData(
      shape: rounded(ArcColors.cardRadius,
          side: highContrast ? outlineSide : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerLow,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      shape: rounded(ArcColors.dialogRadius,
          side: highContrast ? outlineSide : BorderSide.none),
      backgroundColor: colorScheme.surfaceContainerHigh,
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ArcColors.sheetRadius),
        ),
        side: highContrast ? outlineSide : BorderSide.none,
      ),
      elevation: 0,
    ),
    chipTheme: ChipThemeData(
      shape: rounded(ArcColors.pillRadius),
      side: highContrast
          ? BorderSide(color: colorScheme.outline, width: 1.5)
          : BorderSide.none,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(width: outlineWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(width: outlineWidth, color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(
            width: highContrast ? 3.0 : 2.0, color: colorScheme.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(width: outlineWidth, color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(
            width: highContrast ? 3.0 : 2.0, color: colorScheme.error),
      ),
      filled: true,
      fillColor: highContrast
          ? colorScheme.surface
          : colorScheme.surfaceContainerHighest,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor:
          highContrast ? colorScheme.surface : colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: highContrast
          ? colorScheme.primary
          : accentColor?.withValues(alpha: isLight ? 0.16 : 0.24),
      indicatorShape: rounded(ArcColors.buttonRadius),
      iconTheme: highContrast
          ? WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ))
          : null,
    ),
    dividerTheme: DividerThemeData(
      color: highContrast ? colorScheme.outline : colorScheme.outlineVariant,
      space: 1,
      thickness: highContrast ? 2 : 1,
    ),
    listTileTheme: const ListTileThemeData(
      minTileHeight: ArcColors.minRowHeight,
      contentPadding: EdgeInsets.symmetric(horizontal: ArcColors.screenPadding),
      dense: true,
      visualDensity: VisualDensity(horizontal: -1, vertical: -1),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerHigh,
      shape: rounded(ArcColors.buttonRadius,
          side: highContrast ? outlineSide : BorderSide.none),
      menuPadding: EdgeInsets.zero,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: ArcColors.space12),
        ),
        shape: WidgetStatePropertyAll(buttonShape),
        side: highContrast ? WidgetStatePropertyAll(outlineSide) : null,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: highContrast ? hcButtonShape : buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        side: BorderSide(width: outlineWidth, color: colorScheme.outline),
        shape: buttonShape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: highContrast ? hcButtonShape : buttonShape,
      ),
    ),
    extensions: [ArcContrast(highContrast: highContrast)],
  ));

  if (highContrast) {
    theme = theme.copyWith(
      snackBarTheme: theme.snackBarTheme.copyWith(
        shape: rounded(ArcColors.buttonRadius, side: outlineSide),
      ),
      tooltipTheme: theme.tooltipTheme.copyWith(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline, width: 2),
        ),
      ),
    );
  }
  return theme;
}
