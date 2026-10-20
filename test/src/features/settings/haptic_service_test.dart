import 'dart:async';

import 'package:arcpdf/src/features/settings/haptic_service.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
// The existing vibration dependency exposes its platform implementation here.
// ignore: depend_on_referenced_packages
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

class MockBox extends Mock implements Box {}

// The plugin checks dart:io's host OS before querying capabilities. Forward
// these through a channel so Android service behavior is testable on desktop.
class ChannelVibration extends VibrationPlatform {
  static const channel = MethodChannel('vibration');

  @override
  Future<bool> hasVibrator() async =>
      await channel.invokeMethod<bool>('hasVibrator') ?? false;

  @override
  Future<bool> hasAmplitudeControl() async =>
      await channel.invokeMethod<bool>('hasAmplitudeControl') ?? false;

  @override
  Future<void> vibrate({
    int duration = 500,
    List<int> pattern = const [],
    int repeat = -1,
    List<int> intensities = const [],
    int amplitude = -1,
    double sharpness = 0.5,
  }) =>
      channel.invokeMethod<void>('vibrate', {
        'duration': duration,
        'amplitude': amplitude,
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;
  late SettingsController settings;
  late HapticService service;
  late List<MethodCall> vibrationCalls;
  late List<MethodCall> fallbackCalls;
  late VibrationPlatform originalPlatform;
  bool hasVibrator = true;
  bool hasAmplitude = true;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    originalPlatform = VibrationPlatform.instance;
    VibrationPlatform.instance = ChannelVibration();
    hasVibrator = true;
    hasAmplitude = true;
    vibrationCalls = [];
    fallbackCalls = [];
    final box = MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    when(() => box.put(any(), any())).thenAnswer((_) async {});
    settings = SettingsController(box);
    container = ProviderContainer(overrides: [
      settingsControllerProvider.overrideWith((ref) => settings),
    ]);
    service = container.read(hapticServiceProvider);
    messenger.setMockMethodCallHandler(ChannelVibration.channel, (call) async {
      vibrationCalls.add(call);
      return switch (call.method) {
        'hasVibrator' => hasVibrator,
        'hasAmplitudeControl' => hasAmplitude,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      fallbackCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    container.dispose();
    VibrationPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(ChannelVibration.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('all Android feedback uses one vibration and caches capabilities',
      () async {
    await service.selectionClick();
    await service.lightImpact();
    await service.mediumImpact();
    await service.heavyImpact();
    await service.vibrate();
    expect(
        vibrationCalls.where((c) => c.method == 'hasVibrator'), hasLength(1));
    expect(vibrationCalls.where((c) => c.method == 'hasAmplitudeControl'),
        hasLength(1));
    final pulses = vibrationCalls.where((c) => c.method == 'vibrate').toList();
    expect(pulses.map((c) => c.arguments['duration']), [20, 25, 35, 50, 45]);
    expect(
        pulses.map((c) => c.arguments['amplitude']), [90, 100, 160, 220, 180]);
    expect(fallbackCalls, isEmpty);
  });

  test('disabled preference suppresses capability queries and every feedback',
      () async {
    await settings.setUseHaptics(false);
    await service.lightImpact();
    await service.mediumImpact();
    await service.heavyImpact();
    await service.selectionClick();
    await service.vibrate();
    expect(vibrationCalls, isEmpty);
    expect(fallbackCalls, isEmpty);
    await settings.setUseHaptics(true);
    await service.vibrate();
    expect(vibrationCalls.where((c) => c.method == 'vibrate'), hasLength(1));
  });

  test('uses device default amplitude when amplitude control is unavailable',
      () async {
    hasAmplitude = false;
    await service.vibrate();
    expect(vibrationCalls.last.arguments['amplitude'], -1);
    expect(fallbackCalls, isEmpty);
  });

  test('failed amplitude query still uses default-amplitude vibration',
      () async {
    messenger.setMockMethodCallHandler(ChannelVibration.channel, (call) async {
      vibrationCalls.add(call);
      if (call.method == 'hasVibrator') return true;
      if (call.method == 'hasAmplitudeControl') {
        throw PlatformException(code: 'unsupported');
      }
      return null;
    });
    await service.vibrate();
    expect(vibrationCalls.last.arguments['amplitude'], -1);
    expect(fallbackCalls, isEmpty);
  });

  test('no vibrator caches absence and uses matching platform feedback',
      () async {
    hasVibrator = false;
    await service.selectionClick();
    await service.heavyImpact();
    expect(vibrationCalls.map((c) => c.method), ['hasVibrator']);
    expect(fallbackCalls.map((c) => c.arguments), [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  for (final failedMethod in ['hasVibrator', 'vibrate']) {
    test('$failedMethod failure falls back once and contains platform errors',
        () async {
      messenger.setMockMethodCallHandler(ChannelVibration.channel,
          (call) async {
        vibrationCalls.add(call);
        if (call.method == failedMethod) {
          throw PlatformException(code: 'failed');
        }
        return true;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        fallbackCalls.add(call);
        throw MissingPluginException();
      });
      await expectLater(service.mediumImpact(), completes);
      expect(fallbackCalls, hasLength(1));
    });
  }

  test('missing vibration plugin falls back safely', () async {
    messenger.setMockMethodCallHandler(ChannelVibration.channel, null);
    await service.lightImpact();
    expect(fallbackCalls.single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('pending capabilities are shared and preference is rechecked', () async {
    final capability = Completer<bool>();
    messenger.setMockMethodCallHandler(ChannelVibration.channel, (call) async {
      vibrationCalls.add(call);
      if (call.method == 'hasVibrator') return capability.future;
      return true;
    });
    final first = service.lightImpact();
    final second = service.heavyImpact();
    await settings.setUseHaptics(false);
    capability.complete(true);
    await Future.wait([first, second]);
    expect(
        vibrationCalls.where((c) => c.method == 'hasVibrator'), hasLength(1));
    expect(vibrationCalls.where((c) => c.method == 'vibrate'), isEmpty);
    expect(fallbackCalls, isEmpty);
  });

  test('non-Android uses native feedback without querying vibration plugin',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await service.selectionClick();
    await service.vibrate();
    expect(vibrationCalls, isEmpty);
    expect(fallbackCalls.map((c) => c.arguments), [
      'HapticFeedbackType.selectionClick',
      null,
    ]);
  });
}
