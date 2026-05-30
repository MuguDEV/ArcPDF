import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../data/local_boxes.dart';

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
    required this.useGrid,
    required this.useBlurEffect,
    required this.useLiquidGlass,
    required this.animationIntensity,
    required this.animationSpeed,
    required this.thumbnailQuality,
    required this.fontFamily,
    required this.useHaptics,
    required this.keepScreenAwake,
  });

  final ThemeMode themeMode;
  final bool useGrid;
  final bool useBlurEffect;
  final bool useLiquidGlass;
  final double animationIntensity;
  final double animationSpeed;
  final double thumbnailQuality;
  final AppFontFamily fontFamily;
  final bool useHaptics;
  final bool keepScreenAwake;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? useGrid,
    bool? useBlurEffect,
    bool? useLiquidGlass,
    double? animationIntensity,
    double? animationSpeed,
    double? thumbnailQuality,
    AppFontFamily? fontFamily,
    bool? useHaptics,
    bool? keepScreenAwake,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      useGrid: useGrid ?? this.useGrid,
      useBlurEffect: useBlurEffect ?? this.useBlurEffect,
      useLiquidGlass: useLiquidGlass ?? this.useLiquidGlass,
      animationIntensity: animationIntensity ?? this.animationIntensity,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      thumbnailQuality: thumbnailQuality ?? this.thumbnailQuality,
      fontFamily: fontFamily ?? this.fontFamily,
      useHaptics: useHaptics ?? this.useHaptics,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    );
  }
}

// ─── Controller ──────────────────────────────────────────────────────────────

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._box)
      : super(AppSettings(
          themeMode: ThemeMode.values[_box.get('themeMode', defaultValue: 0) as int],
          useGrid: _box.get('grid', defaultValue: false) as bool,
          useBlurEffect: _box.get('useBlurEffect', defaultValue: true) as bool,
          useLiquidGlass: _box.get('useLiquidGlass', defaultValue: false) as bool,
          animationIntensity: ((_box.get('anim', defaultValue: 1.0) as num).toDouble()).clamp(0.01, 1.0),
          animationSpeed: ((_box.get('animSpeed', defaultValue: 1.0) as num).toDouble()).clamp(0.5, 2.0),
          thumbnailQuality: ((_box.get('thumbQ', defaultValue: 0.8) as num).toDouble()).clamp(0.01, 1.0),
          fontFamily: AppFontFamily.values[_box.get('fontFamily', defaultValue: 1) as int],
          useHaptics: _box.get('useHaptics', defaultValue: true) as bool,
          keepScreenAwake: _box.get('keepScreenAwake', defaultValue: false) ?? false,
        ));

  final Box _box;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _box.put('themeMode', mode.index);
  }

  Future<void> setGrid(bool value) async {
    state = state.copyWith(useGrid: value);
    await _box.put('grid', value);
  }

  Future<void> setUseBlurEffect(bool value) async {
    state = state.copyWith(useBlurEffect: value);
    await _box.put('useBlurEffect', value);
  }

  Future<void> setUseLiquidGlass(bool value) async {
    state = state.copyWith(useLiquidGlass: value);
    await _box.put('useLiquidGlass', value);
  }

  Future<void> setAnimationIntensity(double value) async {
    state = state.copyWith(animationIntensity: value);
    await _box.put('anim', value);
  }

  Future<void> setAnimationSpeed(double value) async {
    state = state.copyWith(animationSpeed: value);
    await _box.put('animSpeed', value);
  }

  Future<void> setThumbnailQuality(double value) async {
    state = state.copyWith(thumbnailQuality: value);
    await _box.put('thumbQ', value);
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
}

final settingsControllerProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(Hive.box(LocalBoxes.settings)),
);
