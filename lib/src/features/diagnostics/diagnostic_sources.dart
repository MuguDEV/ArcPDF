import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/utils/logger.dart';
import '../pdf/application/open_tabs_provider.dart';
import '../pdf/application/pdf_library_controller.dart';
import '../settings/settings_controller.dart';
import 'diagnostic_bundle_builder.dart';
import 'diagnostics_session_marker.dart';

/// Production data sources for [DiagnosticBundleBuilder]. Each one reads only
/// an explicit allowlist of non-sensitive fields; nothing is copied wholesale
/// from a plugin or provider.
abstract final class DiagnosticSources {
  /// Wires the builder to real plugins, the log archive and (when given) app
  /// state. Anything left unavailable degrades its own section only.
  static DiagnosticBundleBuilder builder({
    ProviderContainer? container,
    MediaQueryData? media,
    DiagnosticsSessionMarker? marker,
  }) {
    final sessionMarker = marker ?? DiagnosticsSessionMarker.instance;
    return DiagnosticBundleBuilder(
      app: () => app(),
      device: () => device(),
      view: () => display(media: media),
      settings: () => settings(container),
      runtime: () => runtime(container),
      session: sessionMarker.toReport,
      logs: logs,
    );
  }

  static Future<Map<String, Object?>> app(
      {Future<PackageInfo> Function()? packageInfo}) async {
    const mode = kReleaseMode
        ? 'release'
        : kProfileMode
            ? 'profile'
            : 'debug';
    final base = <String, Object?>{
      'mode': mode,
      'flavor': const String.fromEnvironment('FLAVOR', defaultValue: 'default'),
    };
    try {
      final info = await (packageInfo ?? PackageInfo.fromPlatform)();
      return {
        'name': info.appName,
        'package': info.packageName,
        'version': info.version,
        'build': info.buildNumber,
        ...base,
      };
    } catch (error) {
      return {
        ...base,
        'package_info_status': 'unavailable',
        'package_info_reason': error.runtimeType.toString(),
      };
    }
  }

  /// Platform basics always come from `dart:io`; the plugin only adds
  /// manufacturer/model/SDK details, and its failure is non-fatal.
  static Future<Map<String, Object?>> device(
      {Future<BaseDeviceInfo> Function()? deviceInfo}) async {
    final fields = <String, Object?>{
      'platform': Platform.operatingSystem,
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      'processors': Platform.numberOfProcessors,
    };
    try {
      fields['process_rss_mb'] = ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {}
    try {
      final info = await (deviceInfo ?? () => DeviceInfoPlugin().deviceInfo)();
      fields.addAll(deviceFieldsFrom(info.data));
    } catch (error) {
      fields['os_version'] = Platform.operatingSystemVersion;
      fields['device_info_status'] = 'unavailable';
      fields['device_info_reason'] = error.runtimeType.toString();
    }
    return fields;
  }

  /// Allowlist extraction from `BaseDeviceInfo.data`. Serial numbers, device
  /// and computer names, user names, IDs and fingerprints are never read.
  @visibleForTesting
  static Map<String, Object?> deviceFieldsFrom(Map<String, dynamic> data) {
    Object? pick(Map<dynamic, dynamic> map, String key) => map[key];
    final out = <String, Object?>{};
    void copy(String from, [String? to]) {
      final value = pick(data, from);
      if (value is bool || value is num || value is String) {
        out[to ?? from] = value;
      }
    }

    copy('manufacturer');
    copy('model');
    copy('isPhysicalDevice');
    copy('isLowRamDevice');
    copy('systemName');
    copy('systemVersion');
    copy('osRelease');
    copy('arch');
    copy('numberOfCores');
    copy('systemMemoryInMegabytes');
    copy('majorVersion', 'windows_major');
    copy('minorVersion', 'windows_minor');
    copy('buildNumber', 'windows_build');
    final abis = pick(data, 'supportedAbis');
    if (abis is List) out['supported_abis'] = abis.whereType<String>().toList();
    final version = pick(data, 'version');
    if (version is Map) {
      final release = pick(version, 'release');
      final sdk = pick(version, 'sdkInt');
      if (release is String) out['os_version'] = release;
      if (sdk is int) out['sdk_int'] = sdk;
    }
    final utsname = pick(data, 'utsname');
    if (utsname is Map) {
      final machine = pick(utsname, 'machine');
      if (machine is String) out['machine'] = machine;
    }
    return out;
  }

  static Map<String, Object?> display({MediaQueryData? media}) {
    if (media != null) {
      final scale = media.textScaler.scale(100) / 100;
      return {
        'logical_size':
            '${media.size.width.toStringAsFixed(0)}x${media.size.height.toStringAsFixed(0)}',
        'device_pixel_ratio': media.devicePixelRatio,
        'text_scale': double.parse(scale.toStringAsFixed(2)),
        'orientation': media.orientation.name,
        'platform_brightness': media.platformBrightness.name,
        'bold_text': media.boldText,
        'reduce_motion': media.disableAnimations,
      };
    }
    final dispatcher = PlatformDispatcher.instance;
    final view = dispatcher.views.isEmpty ? null : dispatcher.views.first;
    return {
      if (view != null) ...{
        'physical_size':
            '${view.physicalSize.width.toStringAsFixed(0)}x${view.physicalSize.height.toStringAsFixed(0)}',
        'device_pixel_ratio': view.devicePixelRatio,
      },
      'text_scale': dispatcher.textScaleFactor,
      'platform_brightness': dispatcher.platformBrightness.name,
    };
  }

  /// Non-sensitive preferences only. Lock, PIN, pattern and vault state live
  /// in other controllers and are deliberately never read here.
  static Map<String, Object?> settings(ProviderContainer? container) {
    if (container == null || !container.exists(settingsControllerProvider)) {
      throw StateError('settings unavailable');
    }
    return settingsFrom(container.read(settingsControllerProvider));
  }

  @visibleForTesting
  static Map<String, Object?> settingsFrom(AppSettings s) => {
        'theme_mode': s.themeMode.name,
        'font_family': s.fontFamily.name,
        'blur_effect': s.useBlurEffect,
        'liquid_glass': s.useLiquidGlass,
        'animation_intensity': s.animationIntensity,
        'animation_speed': s.animationSpeed,
        'thumbnail_quality': s.thumbnailQuality,
        'haptics': s.useHaptics,
        'keep_screen_awake': s.keepScreenAwake,
        'compression_threads': s.compressionThreads,
        'low_power_mode': s.lowPowerMode,
        'gyro_cards': s.enableGyroCards,
        'mesh_background': s.enableMeshBackground,
      };

  /// Counts only: never titles, paths or tags.
  static Map<String, Object?> runtime(ProviderContainer? container) {
    if (container == null) throw StateError('runtime unavailable');
    final fields = <String, Object?>{};
    if (container.exists(pdfLibraryControllerProvider)) {
      final library = container.read(pdfLibraryControllerProvider);
      fields['library_size_bucket'] = libraryBucket(library.items.length);
      fields['favorites_count'] = library.favorites.length;
      fields['library_loading'] = library.loading;
    }
    if (container.exists(openTabsProvider)) {
      fields['open_tabs_count'] = container.read(openTabsProvider).tabs.length;
    }
    if (fields.isEmpty) throw StateError('runtime unavailable');
    return fields;
  }

  @visibleForTesting
  static String libraryBucket(int count) {
    if (count <= 0) return '0';
    if (count <= 10) return '1-10';
    if (count <= 50) return '11-50';
    if (count <= 200) return '51-200';
    if (count <= 1000) return '201-1000';
    return '1000+';
  }

  /// Entries from the whole rotating archive (flushed first); falls back to
  /// the in-memory window when the archive is empty or unreadable.
  static Future<List<LogEntry>> logs() async {
    final entries = <LogEntry>[];
    final raw = await AppLogger.exportLogs();
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) entries.add(LogEntry.fromMap(decoded));
      } catch (_) {
        // Skip a damaged line rather than losing the rest of the archive.
      }
    }
    return entries.isEmpty ? AppLogger.getLogs() : entries;
  }
}
