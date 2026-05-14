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
    required this.animationIntensity,
    required this.animationSpeed,
    required this.thumbnailQuality,
    required this.fontFamily,
  });

  final ThemeMode themeMode;
  final bool useGrid;
  final double animationIntensity;
  final double animationSpeed;
  final double thumbnailQuality;
  final AppFontFamily fontFamily;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? useGrid,
    double? animationIntensity,
    double? animationSpeed,
    double? thumbnailQuality,
    AppFontFamily? fontFamily,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      useGrid: useGrid ?? this.useGrid,
      animationIntensity: animationIntensity ?? this.animationIntensity,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      thumbnailQuality: thumbnailQuality ?? this.thumbnailQuality,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

// ─── Controller ──────────────────────────────────────────────────────────────

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._box)
      : super(AppSettings(
          themeMode: ThemeMode.values[_box.get('themeMode', defaultValue: 0) as int],
          useGrid: _box.get('grid', defaultValue: false) as bool,
          animationIntensity: ((_box.get('anim', defaultValue: 1.0) as num).toDouble()).clamp(0.01, 1.0),
          animationSpeed: ((_box.get('animSpeed', defaultValue: 1.0) as num).toDouble()).clamp(0.5, 2.0),
          thumbnailQuality: ((_box.get('thumbQ', defaultValue: 0.8) as num).toDouble()).clamp(0.01, 1.0),
          fontFamily: AppFontFamily.values[_box.get('fontFamily', defaultValue: 1) as int],
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
}

final settingsControllerProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(Hive.box(LocalBoxes.settings)),
);
