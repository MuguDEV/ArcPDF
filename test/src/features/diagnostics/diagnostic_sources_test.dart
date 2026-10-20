import 'dart:io';

import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/features/diagnostics/diagnostic_sources.dart';
import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('device', () {
    test('keeps only an allowlist of Android fields', () {
      final fields = DiagnosticSources.deviceFieldsFrom({
        'manufacturer': 'Google',
        'model': 'Pixel 7',
        'isPhysicalDevice': true,
        'supportedAbis': ['arm64-v8a'],
        'version': {
          'release': '14',
          'sdkInt': 34,
          'securityPatch': '2026-01-05'
        },
        'serialNumber': 'SN-ABC123',
        'id': 'UQ1A.240105.004',
        'fingerprint': 'google/panther/panther:14/…',
        'device': 'panther',
        'host': 'build-host-7',
        'systemFeatures': ['android.hardware.camera'],
      });
      expect(fields, {
        'manufacturer': 'Google',
        'model': 'Pixel 7',
        'isPhysicalDevice': true,
        'supported_abis': ['arm64-v8a'],
        'os_version': '14',
        'sdk_int': 34,
      });
    });

    test('never reads Windows computer or user names', () {
      final fields = DiagnosticSources.deviceFieldsFrom({
        'computerName': 'ALICE-PC',
        'userName': 'alice',
        'registeredOwner': 'Alice',
        'deviceId': '{1234}',
        'productId': '00330-xxxxx',
        'majorVersion': 10,
        'buildNumber': 22631,
        'numberOfCores': 8,
      });
      expect(fields, {
        'windows_major': 10,
        'windows_build': 22631,
        'numberOfCores': 8,
      });
    });

    test('falls back to platform basics when the plugin throws', () async {
      final fields = await DiagnosticSources.device(
        deviceInfo: () async => throw MissingPluginException(r'C:\x\alice'),
      );
      expect(fields['platform'], Platform.operatingSystem);
      expect(fields['device_info_status'], 'unavailable');
      expect(fields['device_info_reason'], 'MissingPluginException');
      expect(fields.values.join(), isNot(contains('alice')));
      expect(fields, contains('os_version'));
    });
  });

  group('app', () {
    test('reports package info and build mode', () async {
      final fields = await DiagnosticSources.app(
        packageInfo: () async => PackageInfo(
            appName: 'ArcPDF',
            packageName: 'com.arcpdf.app',
            version: '1.4.4',
            buildNumber: '9'),
      );
      expect(fields['name'], 'ArcPDF');
      expect(fields['version'], '1.4.4');
      expect(fields['build'], '9');
      expect(fields['mode'], 'debug');
      expect(fields['flavor'], 'default');
    });

    test('still reports build mode when package info fails', () async {
      final fields = await DiagnosticSources.app(
        packageInfo: () async => throw StateError('no plugin'),
      );
      expect(fields['mode'], 'debug');
      expect(fields['package_info_status'], 'unavailable');
      expect(fields.containsKey('version'), isFalse);
    });
  });

  test('display uses media metrics when provided', () {
    final fields = DiagnosticSources.display(
      media: const MediaQueryData(
        size: Size(390, 844),
        devicePixelRatio: 3,
        textScaler: TextScaler.linear(1.3),
      ),
    );
    expect(fields['logical_size'], '390x844');
    expect(fields['device_pixel_ratio'], 3.0);
    expect(fields['text_scale'], 1.3);
  });

  group('settings and runtime', () {
    test('settings snapshot holds only plain preferences', () {
      final fields = DiagnosticSources.settingsFrom(const AppSettings(
        themeMode: ThemeMode.dark,
        useBlurEffect: true,
        useLiquidGlass: false,
        animationIntensity: 0.5,
        animationSpeed: 1,
        thumbnailQuality: 0.8,
        fontFamily: AppFontFamily.inter,
        useHaptics: true,
        keepScreenAwake: false,
        compressionThreads: 2,
        lowPowerMode: true,
        enableGyroCards: false,
        enableMeshBackground: false,
        skippedUpdateVersion: '9.9.9',
      ));
      expect(fields['theme_mode'], 'dark');
      expect(fields['low_power_mode'], true);
      expect(fields.values, isNot(contains('9.9.9')));
      expect(fields.keys.join(), isNot(contains('pin')));
      expect(fields.keys.join(), isNot(contains('lock')));
    });

    test('unavailable without a container or provider', () {
      expect(() => DiagnosticSources.settings(null), throwsStateError);
      expect(() => DiagnosticSources.runtime(null), throwsStateError);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(() => DiagnosticSources.settings(container), throwsStateError);
      expect(() => DiagnosticSources.runtime(container), throwsStateError);
    });

    test('runtime reports counts only', () async {
      final directory =
          await Directory.systemTemp.createTemp('arcpdf_diag_runtime_');
      Hive.init(directory.path);
      final box = await Hive.openBox<dynamic>('diag_sessions');
      final container = ProviderContainer(overrides: [
        openTabsProvider.overrideWith((ref) => OpenTabsNotifier(box)),
      ]);
      container.read(openTabsProvider);
      try {
        expect(DiagnosticSources.runtime(container), {'open_tabs_count': 0});
      } finally {
        container.dispose();
        await Hive.close();
        await directory.delete(recursive: true);
      }
    });

    test('library size is bucketed', () {
      expect(
          [0, 1, 10, 11, 50, 51, 200, 201, 1000, 1001]
              .map(DiagnosticSources.libraryBucket),
          [
            '0',
            '1-10',
            '1-10',
            '11-50',
            '11-50',
            '51-200',
            '51-200',
            '201-1000',
            '201-1000',
            '1000+'
          ]);
    });
  });

  test('logs come from the full archive, newest data included', () async {
    final directory =
        await Directory.systemTemp.createTemp('arcpdf_diag_logs_');
    Hive.init(directory.path);
    try {
      await AppLogger.init();
      await AppLogger.clearLogs();
      await AppLogger.info('first.event');
      await AppLogger.warning('second.event');
      final logs = await DiagnosticSources.logs();
      expect(logs.map((entry) => entry.message),
          containsAll(['first.event', 'second.event']));
    } finally {
      await AppLogger.flush();
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
