import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/navigation_controller.dart';

final intentServiceProvider = Provider<IntentService>((ref) {
  final service = IntentService(ref);

  ref.listen<bool>(splashDoneProvider, (prev, isDone) {
    if (isDone && !service.splashCompleter.isCompleted) {
      service.splashCompleter.complete();
    }
  });

  return service;
});

class IntentService {
  final Ref ref;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Completer<void> splashCompleter = Completer<void>();

  IntentService(this.ref) {
    if (ref.read(splashDoneProvider)) {
      splashCompleter.complete();
    }
  }

  void init() {
    // Desktop platforms currently do not use receive_sharing_intent.
    // If command line arguments or URI schemes are added for Windows later,
    // they can be handled here.
  }

  void dispose() {
    // No streams to cancel on Windows.
  }
}
