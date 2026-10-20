import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/utils/logger.dart';
import '../../data/local_boxes.dart';

/// Key inside [LocalBoxes.settings]. Deliberately not part of `AppSettings`.
const onboardingCompletedKey = 'onboardingCompleted';

/// Whether any of [boxes] already holds user library history.
///
/// Defensive: a box that is missing, closed, or throws counts as "no history".
bool hasLibraryHistory(Iterable<Box<dynamic>?> boxes) {
  for (final box in boxes) {
    try {
      if (box != null && box.isOpen && box.isNotEmpty) return true;
    } catch (_) {
      // An unreadable box must never block startup or fake a history.
    }
  }
  return false;
}

/// Tracks whether first-run onboarding is finished (`true` = do not show).
///
/// Resolution rule, evaluated once when the notifier is created:
/// 1. The persisted `onboardingCompleted` flag is `true` -> completed.
/// 2. [box] is unavailable or throws -> completed (never trap the user in a
///    flow whose completion cannot be remembered).
/// 3. Any of [historyBoxes] (favorites, recents, saved tabs/reading sessions)
///    is non-empty -> the user predates onboarding: completed, and the flag is
///    persisted so the decision is stable.
/// 4. Otherwise onboarding is pending.
class OnboardingCompletedNotifier extends StateNotifier<bool> {
  OnboardingCompletedNotifier(
    this._box, {
    Iterable<Box<dynamic>?> historyBoxes = const [],
  }) : super(true) {
    _resolve(historyBoxes);
  }

  final Box<dynamic>? _box;

  void _resolve(Iterable<Box<dynamic>?> historyBoxes) {
    final box = _box;
    if (box == null) return;
    try {
      if (box.get(onboardingCompletedKey, defaultValue: false) == true) return;
      if (hasLibraryHistory(historyBoxes)) {
        unawaited(_persist());
        AppLogger.event('onboarding.skipped_existing_user');
        return;
      }
      state = false;
    } catch (_) {
      state = true;
    }
  }

  Future<void> _persist() async {
    try {
      await _box?.put(onboardingCompletedKey, true);
    } catch (_) {
      // Best effort: onboarding may be shown once more after a storage fault.
    }
  }

  /// Marks onboarding finished and persists the decision.
  Future<void> complete() async {
    if (state) return;
    state = true;
    await _persist();
  }
}

/// Override in tests with an injected [Box].
final onboardingCompletedProvider =
    StateNotifierProvider<OnboardingCompletedNotifier, bool>((ref) {
  Box<dynamic>? open(String name) {
    try {
      return Hive.isBoxOpen(name) ? Hive.box<dynamic>(name) : null;
    } catch (_) {
      return null;
    }
  }

  return OnboardingCompletedNotifier(
    open(LocalBoxes.settings),
    historyBoxes: [
      open(LocalBoxes.favorites),
      open(LocalBoxes.recents),
      open(LocalBoxes.sessions),
    ],
  );
});
