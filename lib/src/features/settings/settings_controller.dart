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

  Future<void> setUseBlurEffect(bool value) async {
    state = state.copyWith(useBlurEffect: value);
    await _box.put('useBlurEffect', value);
  }

  Future<void> setUseLiquidGlass(bool value) async {
    state = state.copyWith(useLiquidGlass: value);
    await _box.put('useLiquidGlass', value);
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
  }

  Future<void> setEnableGyroCards(bool value) async {
    state = state.copyWith(enableGyroCards: value);
    await _box.put('enableGyroCards', value);
  }

  Future<void> setEnableMeshBackground(bool value) async {
    state = state.copyWith(enableMeshBackground: value);
    await _box.put('enableMeshBackground', value);
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
  return AppSettings(
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
  );
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(Hive.box(LocalBoxes.settings)),
);
