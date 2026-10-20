import 'dart:ui';

import 'package:arcpdf/src/core/utils/app_diagnostics.dart';
import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/features/navigation/navigation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AppLogger.clearLogs);

  test('captures lifecycle and errors while preserving existing handlers',
      () async {
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    var flutterCalls = 0;
    var platformCalls = 0;
    FlutterError.onError = (_) => flutterCalls++;
    PlatformDispatcher.instance.onError = (_, __) {
      platformCalls++;
      return true;
    };
    try {
      AppDiagnostics.instance.install();
      AppDiagnostics.instance.install();
      FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('private document text'),
        stack: StackTrace.current,
      ));
      expect(
          PlatformDispatcher.instance.onError!(
              StateError('private password'), StackTrace.current),
          isTrue);
      AppDiagnostics.instance
          .didChangeAppLifecycleState(AppLifecycleState.paused);
      AppDiagnostics.instance
          .didChangeAppLifecycleState(AppLifecycleState.detached);
      AppDiagnostics.instance.didHaveMemoryPressure();
      final messages = AppLogger.getLogs().map((e) => e.message).join('\n');
      expect(flutterCalls, 1);
      expect(platformCalls, 1);
      expect(messages, contains('flutter.error [StateError]'));
      expect(messages, contains('platform.error [StateError]'));
      expect(messages, contains('state=paused'));
      expect(messages, contains('state=detached'));
      expect(messages, contains('app.memory_pressure'));
      expect(messages, isNot(contains('private')));
      expect(
          AppLogger.getLogs().where((e) => e.message == 'app.session.started'),
          hasLength(1));
    } finally {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
      WidgetsBinding.instance.removeObserver(AppDiagnostics.instance);
    }
  });

  test('destination logging ignores repeats and rejects invalid indices', () {
    final controller = NavigationController();
    addTearDown(controller.dispose);
    controller.setIndex(0);
    expect(AppLogger.getLogs(), isEmpty);
    controller.setIndex(4);
    expect(controller.state.index, 4);
    expect(AppLogger.getLogs().single.message,
        'navigation.destination from=home to=settings');
    controller.setIndex(99);
    expect(controller.state.index, 4);
    expect(AppLogger.getLogs().first.level, 'WARNING');
  });

  test('provider errors are logged without provider values or exception text',
      () {
    final container = ProviderContainer(observers: [AppLogProviderObserver()]);
    addTearDown(container.dispose);
    final failing =
        Provider<int>((ref) => throw StateError('account password'));
    expect(() => container.read(failing), throwsStateError);
    expect(AppLogger.getLogs().single.message, 'provider.failed [StateError]');
  });

  testWidgets('route observer captures operations without names or arguments',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [AppLogNavigatorObserver()],
      home: const SizedBox(),
    ));
    key.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(
          name: '/private/report.pdf', arguments: 'secret document contents'),
      builder: (_) => const SizedBox(),
    ));
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    final messages = AppLogger.getLogs().map((e) => e.message).join('\n');
    expect(messages, contains('navigation.push'));
    expect(messages, contains('navigation.pop'));
    expect(messages, isNot(contains('private')));
    expect(messages, isNot(contains('secret')));
  });
}
