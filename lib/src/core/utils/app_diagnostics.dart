import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logger.dart';

/// Install after ensureInitialized(), before bootstrap, in the runApp zone.
/// Existing Flutter/platform error handlers are preserved rather than replaced.
class AppDiagnostics with WidgetsBindingObserver {
  AppDiagnostics._();

  static final instance = AppDiagnostics._();
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(
          AppLogger.error('flutter.error', details.exception, details.stack));
      unawaited(AppLogger.flush());
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(AppLogger.error('platform.error', error, stack));
      unawaited(AppLogger.flush());
      // Do not silently swallow an error that the application did not handle.
      return previousPlatformHandler?.call(error, stack) ?? false;
    };
    unawaited(AppLogger.event('app.session.started'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(AppLogger.event('app.lifecycle', fields: {'state': state.name}));
    if (state != AppLifecycleState.resumed) {
      unawaited(AppLogger.flush());
    }
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(AppLogger.warning('app.memory_pressure'));
    unawaited(AppLogger.flush());
  }
}

/// Separate from the reader's RouteObserver so reader subscriptions still work.
/// Route arguments and names can contain document paths; neither is inspected.
class AppLogNavigatorObserver extends NavigatorObserver {
  void _log(String action, Route<dynamic>? route) {
    if (route == null) return;
    unawaited(AppLogger.event('navigation.$action', fields: {
      'routeType': route.runtimeType.toString(),
      'routeId': identityHashCode(route),
      'popup': route is PopupRoute,
    }));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('push', route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('pop', route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('remove', route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _log('replace.old', oldRoute);
    _log('replace.new', newRoute);
  }
}

/// Never serialize provider values: they include passwords and document data.
class AppLogProviderObserver extends ProviderObserver {
  @override
  void providerDidFail(ProviderBase<Object?> provider, Object error,
      StackTrace stackTrace, ProviderContainer container) {
    unawaited(AppLogger.error('provider.failed', error, stackTrace));
  }
}
