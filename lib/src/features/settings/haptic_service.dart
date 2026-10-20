import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'settings_controller.dart';

class HapticService {
  HapticService(this.ref);
  final Ref ref;

  Future<({bool vibrator, bool amplitude})>? _capabilities;

  bool get _isEnabled => ref.read(settingsControllerProvider).useHaptics;

  Future<({bool vibrator, bool amplitude})> _loadCapabilities() async {
    try {
      if (!await Vibration.hasVibrator()) {
        return (vibrator: false, amplitude: false);
      }
    } catch (_) {
      return (vibrator: false, amplitude: false);
    }
    try {
      return (vibrator: true, amplitude: await Vibration.hasAmplitudeControl());
    } catch (_) {
      // A device can still vibrate using its default amplitude.
      return (vibrator: true, amplitude: false);
    }
  }

  Future<void> _play(
    Future<void> Function() fallback, {
    required int duration,
    required int amplitude,
  }) async {
    if (!_isEnabled) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final capabilities = await (_capabilities ??= _loadCapabilities());
      // The preference may have changed while the platform query was pending.
      if (!_isEnabled) return;
      if (capabilities.vibrator) {
        try {
          await Vibration.vibrate(
            duration: duration,
            amplitude: capabilities.amplitude ? amplitude : -1,
          );
          return; // Never follow a successful vibration with another buzz.
        } catch (_) {
          // Missing or failing plugins must not break the interaction.
        }
      }
    }
    if (!_isEnabled) return;
    try {
      await fallback();
    } catch (_) {
      // Haptics are optional, including on unsupported platforms.
    }
  }

  Future<void> lightImpact() =>
      _play(HapticFeedback.lightImpact, duration: 25, amplitude: 100);

  Future<void> mediumImpact() =>
      _play(HapticFeedback.mediumImpact, duration: 35, amplitude: 160);

  Future<void> heavyImpact() =>
      _play(HapticFeedback.heavyImpact, duration: 50, amplitude: 220);

  Future<void> selectionClick() =>
      _play(HapticFeedback.selectionClick, duration: 20, amplitude: 90);

  Future<void> vibrate() =>
      _play(HapticFeedback.vibrate, duration: 45, amplitude: 180);
}

final hapticServiceProvider =
    Provider<HapticService>((ref) => HapticService(ref));
