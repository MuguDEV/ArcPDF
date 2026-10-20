import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../data/local_boxes.dart';
import '../../shared/theme/arc_accent.dart';
import '../../shared/theme/arc_theme.dart' show HighContrastMode;

export '../../shared/theme/arc_accent.dart' show ArcAccent, ArcAccentX;
export '../../shared/theme/arc_theme.dart'
    show HighContrastMode, HighContrastModeX;

// ─── Performance preset ─────────────────────────────────────────────────────

/// Bundles of effect settings. [custom] means the individual toggles do not
/// match any named preset.
enum PerformancePreset { smooth, balanced, battery, custom }

extension PerformancePresetX on PerformancePreset {
  String get displayName => switch (this) {
        PerformancePreset.smooth => 'Smooth',
        PerformancePreset.balanced => 'Balanced',
        PerformancePreset.battery => 'Battery',
        PerformancePreset.custom => 'Custom',
      };

  String get description => switch (this) {
        PerformancePreset.smooth =>
          'Blur, liquid glass and animated background. Largest reader cache.',
        PerformancePreset.balanced =>
          'Blur only. A good mix of looks and efficiency.',
        PerformancePreset.battery =>
          'Low power mode, no blur or animated background. Smallest cache.',
        PerformancePreset.custom =>
          'Your individual settings do not match a preset.',
      };
}

// ─── Font family ────────────────────────────────────────────────────────────

enum AppFontFamily { system, inter, roboto, plusJakarta, nunito }

extension AppFontFamilyX on AppFontFamily {
  String get displayName => switch (this) {
        AppFontFamily.system => 'System',
        AppFontFamily.inter => 'Inter',
        AppFontFamily.roboto => 'Roboto',
        AppFontFamily.plusJakarta => 'Plus Jakarta',
        AppFontFamily.nunito => 'Nunito',
      };

  /// The Google Fonts package name (null = system default).
  String? get googleFontName => switch (this) {
        AppFontFamily.system => null,
        AppFontFamily.inter => 'Inter',
        AppFontFamily.roboto => 'Roboto',
        AppFontFamily.plusJakarta => 'Plus Jakarta Sans',
        AppFontFamily.nunito => 'Nunito',
      };
}

// ─── Settings model ─────────────────────────────────────────────────────────

@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.useBlurEffect,
    required this.useLiquidGlass,
    required this.animationIntensity,
    required this.animationSpeed,
    required this.thumbnailQuality,
    required this.fontFamily,
    required this.useHaptics,
    required this.keepScreenAwake,
    required this.compressionThreads,
    required this.lowPowerMode,
    required this.enableGyroCards,
    required this.enableMeshBackground,
    this.skippedUpdateVersion,
    this.performancePreset = PerformancePreset.balanced,
    this.accent = ArcAccent.none,
    this.highContrast = HighContrastMode.system,
  });

  final ThemeMode themeMode;
  final bool useBlurEffect;
  final bool useLiquidGlass;
  final double animationIntensity;
  final double animationSpeed;
  final double thumbnailQuality;
  final AppFontFamily fontFamily;
  final bool useHaptics;
  final bool keepScreenAwake;
  final int compressionThreads;
  final bool lowPowerMode;
  final bool enableGyroCards;
  final bool enableMeshBackground;
  final String? skippedUpdateVersion;
  final PerformancePreset performancePreset;
  final ArcAccent accent;
  final HighContrastMode highContrast;

  /// The named preset the individual settings currently match, or
  /// [PerformancePreset.custom] when they diverge from all of them.
  PerformancePreset get matchingPreset {
    for (final preset in const [
      PerformancePreset.smooth,
      PerformancePreset.balanced,
      PerformancePreset.battery,
    ]) {
      if (_matches(preset)) return preset;
    }
    return PerformancePreset.custom;
  }

  bool _matches(PerformancePreset preset) => switch (preset) {
        PerformancePreset.smooth => useBlurEffect &&
            useLiquidGlass &&
            enableMeshBackground &&
            !lowPowerMode &&
            animationSpeed == 1.0,
        PerformancePreset.balanced => useBlurEffect &&
            !useLiquidGlass &&
            !enableMeshBackground &&
            !lowPowerMode &&
            animationSpeed == 1.0,
        PerformancePreset.battery => lowPowerMode &&
            !useBlurEffect &&
            !useLiquidGlass &&
            !enableMeshBackground,
        PerformancePreset.custom => false,
      };

  /// Preset used for derived performance budgets. Custom setups fall back to
  /// the closest tier based on the individual toggles.
  PerformancePreset get _budgetTier {
    if (performancePreset != PerformancePreset.custom) return performancePreset;
    if (lowPowerMode) return PerformancePreset.battery;
    if (useBlurEffect && (useLiquidGlass || enableMeshBackground)) {
      return PerformancePreset.smooth;
    }
    return PerformancePreset.balanced;
  }

  /// Memory budget (MB) the reader may use for rendered page caching.
  int get readerCacheMb => switch (_budgetTier) {
        PerformancePreset.smooth => 96,
        PerformancePreset.battery => 48,
        _ => 80,
      };

  /// How far (in viewport heights) the reader pre-renders beyond the screen.
  double get readerPreloadExtent => switch (_budgetTier) {
        PerformancePreset.smooth => 1.0,
        PerformancePreset.battery => 0.25,
        _ => 0.5,
      };

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? useBlurEffect,
    bool? useLiquidGlass,
    double? animationIntensity,
    double? animationSpeed,
    double? thumbnailQuality,
    AppFontFamily? fontFamily,
    bool? useHaptics,
    bool? keepScreenAwake,
    int? compressionThreads,
    bool? lowPowerMode,
    bool? enableGyroCards,
    bool? enableMeshBackground,
    String? skippedUpdateVersion,
    PerformancePreset? performancePreset,
    ArcAccent? accent,
    HighContrastMode? highContrast,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      useBlurEffect: useBlurEffect ?? this.useBlurEffect,
      useLiquidGlass: useLiquidGlass ?? this.useLiquidGlass,
      animationIntensity: animationIntensity ?? this.animationIntensity,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      thumbnailQuality: thumbnailQuality ?? this.thumbnailQuality,
      fontFamily: fontFamily ?? this.fontFamily,
      useHaptics: useHaptics ?? this.useHaptics,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
      compressionThreads: compressionThreads ?? this.compressionThreads,
      lowPowerMode: lowPowerMode ?? this.lowPowerMode,
      enableGyroCards: enableGyroCards ?? this.enableGyroCards,
      enableMeshBackground: enableMeshBackground ?? this.enableMeshBackground,
      skippedUpdateVersion: skippedUpdateVersion ?? this.skippedUpdateVersion,
      performancePreset: performancePreset ?? this.performancePreset,
      accent: accent ?? this.accent,
      highContrast: highContrast ?? this.highContrast,
    );
  }
}

// ─── Controller ──────────────────────────────────────────────────────────────

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._box) : super(_loadSettings(_box));

  final Box _box;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _box.put('themeMode', mode.index);
  }

  Future<void> setAccent(ArcAccent accent) async {
    state = state.copyWith(accent: accent);
    await _box.put('accent', accent.index);
  }

  Future<void> setHighContrast(HighContrastMode mode) async {
    state = state.copyWith(highContrast: mode);
    await _box.put('highContrast', mode.index);
  }

  /// Applies [preset] by writing the underlying individual settings.
  /// [PerformancePreset.custom] keeps the current values and only marks the
  /// configuration as custom until the next effect change.
  Future<void> setPerformancePreset(PerformancePreset preset) async {
    switch (preset) {
      case PerformancePreset.custom:
        break;
      case PerformancePreset.smooth:
        state = state.copyWith(
          useBlurEffect: true,
          useLiquidGlass: true,
          enableMeshBackground: true,
          lowPowerMode: false,
          animationSpeed: 1.0,
        );
      case PerformancePreset.balanced:
        state = state.copyWith(
          useBlurEffect: true,
          useLiquidGlass: false,
          enableMeshBackground: false,
          lowPowerMode: false,
          animationSpeed: 1.0,
        );
      case PerformancePreset.battery:
        state = state.copyWith(
          useBlurEffect: false,
          useLiquidGlass: false,
          enableMeshBackground: false,
          lowPowerMode: true,
        );
    }
    state = state.copyWith(performancePreset: preset);
    if (preset != PerformancePreset.custom) {
      await _box.put('useBlurEffect', state.useBlurEffect);
      await _box.put('useLiquidGlass', state.useLiquidGlass);
      await _box.put('enableMeshBackground', state.enableMeshBackground);
      await _box.put('lowPowerMode', state.lowPowerMode);
      if (preset != PerformancePreset.battery) {
        await _box.put('animSpeed', state.animationSpeed);
      }
    }
    await _box.put('performancePreset', preset.index);
  }

  /// Re-derives the preset after an individual effect setting changed.
  Future<void> _syncPreset() async {
    final matching = state.matchingPreset;
    if (matching == state.performancePreset) return;
    state = state.copyWith(performancePreset: matching);
    await _box.put('performancePreset', matching.index);
  }

  Future<void> setUseBlurEffect(bool value) async {
    state = state.copyWith(useBlurEffect: value);
    await _box.put('useBlurEffect', value);
    await _syncPreset();
  }

  Future<void> setUseLiquidGlass(bool value) async {
    state = state.copyWith(useLiquidGlass: value);
    await _box.put('useLiquidGlass', value);
    await _syncPreset();
  }

  Future<void> setAnimationIntensity(double value) async {
    final valid = _finiteRange(value, state.animationIntensity, 0.01, 1);
    state = state.copyWith(animationIntensity: valid);
    await _box.put('anim', valid);
  }

  Future<void> setAnimationSpeed(double value) async {
    final valid = _finiteRange(value, state.animationSpeed, 0.5, 2);
    state = state.copyWith(animationSpeed: valid);
    await _box.put('animSpeed', valid);
    await _syncPreset();
  }

  Future<void> setThumbnailQuality(double value) async {
    final valid = _finiteRange(value, state.thumbnailQuality, 0.01, 1);
    state = state.copyWith(thumbnailQuality: valid);
    await _box.put('thumbQ', valid);
  }

  Future<void> setFontFamily(AppFontFamily family) async {
    state = state.copyWith(fontFamily: family);
    await _box.put('fontFamily', family.index);
  }

  Future<void> setUseHaptics(bool value) async {
    state = state.copyWith(useHaptics: value);
    await _box.put('useHaptics', value);
  }

  Future<void> setKeepScreenAwake(bool value) async {
    state = state.copyWith(keepScreenAwake: value);
    await _box.put('keepScreenAwake', value);
  }

  Future<void> setCompressionThreads(int value) async {
    final clamped = value.clamp(1, 5);
    state = state.copyWith(compressionThreads: clamped);
    await _box.put('compressionThreads', clamped);
  }

  Future<void> setLowPowerMode(bool value) async {
    state = state.copyWith(lowPowerMode: value);
    await _box.put('lowPowerMode', value);
    await _syncPreset();
  }

  Future<void> setEnableGyroCards(bool value) async {
    state = state.copyWith(enableGyroCards: value);
    await _box.put('enableGyroCards', value);
  }

  Future<void> setEnableMeshBackground(bool value) async {
    state = state.copyWith(enableMeshBackground: value);
    await _box.put('enableMeshBackground', value);
    await _syncPreset();
  }

  Future<void> setSkippedUpdateVersion(String version) async {
    state = state.copyWith(skippedUpdateVersion: version);
    await _box.put('skippedUpdateVersion', version);
  }
}

double _finiteRange(Object? value, double fallback, double min, double max) {
  if (value is! num || !value.isFinite) return fallback;
  return value.toDouble().clamp(min, max);
}

AppSettings _loadSettings(Box box) {
  bool flag(String key, bool fallback) {
    final value = box.get(key, defaultValue: fallback);
    return value is bool ? value : fallback;
  }

  T choice<T>(String key, List<T> values, int fallback) {
    final index = box.get(key, defaultValue: fallback);
    return index is int && index >= 0 && index < values.length
        ? values[index]
        : values[fallback];
  }

  double number(String key, double fallback, double min, double max) =>
      _finiteRange(box.get(key, defaultValue: fallback), fallback, min, max);
  final skippedVersion = box.get('skippedUpdateVersion');
  final base = AppSettings(
    themeMode: choice('themeMode', ThemeMode.values, 0),
    fontFamily: choice('fontFamily', AppFontFamily.values, 1),
    useBlurEffect: flag('useBlurEffect', true),
    useLiquidGlass: flag('useLiquidGlass', false),
    animationIntensity: number('anim', 1, 0.01, 1),
    animationSpeed: number('animSpeed', 1, 0.5, 2),
    thumbnailQuality: number('thumbQ', 0.8, 0.01, 1),
    useHaptics: flag('useHaptics', true),
    keepScreenAwake: flag('keepScreenAwake', false),
    compressionThreads: number('compressionThreads', 2, 1, 5).toInt(),
    lowPowerMode: flag('lowPowerMode', false),
    enableGyroCards: flag('enableGyroCards', false),
    enableMeshBackground: flag('enableMeshBackground', false),
    skippedUpdateVersion: skippedVersion is String ? skippedVersion : null,
    accent: choice('accent', ArcAccent.values, 0),
    highContrast: choice('highContrast', HighContrastMode.values, 1),
  );
  // Keep a stored preset only while the individual settings still match it
  // (or it is explicitly custom); otherwise derive it. Older installs have no
  // stored preset and are derived from their existing toggles.
  final stored = choice('performancePreset', PerformancePreset.values, 1);
  final matching = base.matchingPreset;
  final hasStored = box.get('performancePreset') is int;
  return base.copyWith(
    performancePreset: hasStored && stored == PerformancePreset.custom
        ? PerformancePreset.custom
        : matching,
  );
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(Hive.box(LocalBoxes.settings)),
);
