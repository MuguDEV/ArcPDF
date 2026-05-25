import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'settings_controller.dart';

class HapticService {
  HapticService(this.ref);
  final Ref ref;

  bool get _isEnabled => ref.read(settingsControllerProvider).useHaptics;

  Future<void> lightImpact() async {
    if (!_isEnabled) return;
    HapticFeedback.lightImpact();
  }

  Future<void> mediumImpact() async {
    if (!_isEnabled) return;
    HapticFeedback.mediumImpact();
  }

  Future<void> heavyImpact() async {
    if (!_isEnabled) return;
    HapticFeedback.heavyImpact();
  }

  Future<void> selectionClick() async {
    if (!_isEnabled) return;
    HapticFeedback.selectionClick();
  }

  Future<void> vibrate() async {
    if (!_isEnabled) return;
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 15, amplitude: 50);
    } else {
      HapticFeedback.selectionClick();
    }
  }
}

final hapticServiceProvider = Provider<HapticService>((ref) => HapticService(ref));
