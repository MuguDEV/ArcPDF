import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/features/security/lock_screen.dart';
import 'package:arcpdf/src/features/security/pin_pad.dart';
import 'package:arcpdf/src/features/security/security_controller.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/local_auth');
  late Directory root;
  late Box settings;
  late ProviderContainer container;
  late SecurityController security;
  late Completer<bool> authentication;
  late int prompts;
  late bool available;
  late bool throwOnAuthenticate;
  late List<dynamic> options;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('arcpdf_auth_');
    Hive.init(root.path);
    settings = await Hive.openBox('security_settings');
    await settings.putAll({
      'isLockEnabled': true,
      'isBiometricEnabled': true,
      'lowPowerMode': true,
      'useHaptics': false,
    });
    FlutterSecureStorage.setMockInitialValues({});
    authentication = Completer<bool>();
    prompts = 0;
    available = true;
    throwOnAuthenticate = false;
    options = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      switch (call.method) {
        case 'getAvailableBiometrics':
          return available ? ['fingerprint'] : <String>[];
        case 'isDeviceSupported':
          return available;
        case 'authenticate':
          prompts++;
          options.add(call.arguments);
          if (throwOnAuthenticate) {
            throw PlatformException(code: 'NotAvailable');
          }
          return authentication.future;
        default:
          throw StateError('Unexpected local_auth call: ${call.method}');
      }
    });
    security = SecurityController(settings);
    container = ProviderContainer(overrides: [
      securityControllerProvider.overrideWith((ref) => security),
      settingsControllerProvider
          .overrideWith((ref) => SettingsController(settings)),
    ]);
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    container.dispose();
    await settings.close();
    await root.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: LockScreenWrapper(child: Scaffold(body: Text('Protected'))),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> lifecycle(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  Future<void> completeAuthentication(WidgetTester tester, bool result) async {
    await tester.runAsync(() async {
      authentication.complete(result);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
      'cancel stays locked across repeated lifecycle resumes and rebuilds',
      (tester) async {
    await mount(tester);
    expect(prompts, 1);
    await completeAuthentication(tester, false);
    await lifecycle(tester);
    await lifecycle(tester);
    await mount(tester);
    expect(prompts, 1);
    expect(container.read(securityControllerProvider).isLocked, true);
    expect(find.text('App Locked'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('manual retry works and repeated taps share one native prompt',
      (tester) async {
    await mount(tester);
    await completeAuthentication(tester, false);
    authentication = Completer<bool>();
    await tester.ensureVisible(find.text('Use Biometrics'));
    await tester.tap(find.text('Use Biometrics'));
    await tester.tap(find.text('Use Biometrics'));
    await tester.pump();
    expect(prompts, 2);
    await lifecycle(tester);
    expect(prompts, 2);
    await completeAuthentication(tester, true);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(prompts, 2);
    expect(container.read(securityControllerProvider).isLocked, false);
    expect(find.text('App Locked'), findsNothing);
    await unmount(tester);
  });

  testWidgets('native dialog lifecycle does not relock an unlocked app',
      (tester) async {
    security.unlockApp();
    await mount(tester);
    final result = security.authenticateBiometric();
    await tester.pump();
    expect(security.isAuthenticating, true);
    await lifecycle(tester);
    expect(container.read(securityControllerProvider).isLocked, false);
    await completeAuthentication(tester, false);
    expect(await result, false);
    await tester.pump();
    expect(prompts, 1);
    await unmount(tester);
  });

  testWidgets('fresh lock session gets one new automatic attempt',
      (tester) async {
    await mount(tester);
    await completeAuthentication(tester, true);
    expect(container.read(securityControllerProvider).isLocked, false);
    authentication = Completer<bool>();
    await lifecycle(tester);
    expect(prompts, 2);
    await completeAuthentication(tester, false);
    await lifecycle(tester);
    expect(prompts, 2);
    expect(container.read(securityControllerProvider).isLocked, true);
    await unmount(tester);
  });

  testWidgets('platform failure does not auto retry but explicit retry works',
      (tester) async {
    throwOnAuthenticate = true;
    await mount(tester);
    await lifecycle(tester);
    expect(prompts, 1);
    expect(container.read(securityControllerProvider).isLocked, true);
    throwOnAuthenticate = false;
    await tester.ensureVisible(find.text('Use Biometrics'));
    await tester.tap(find.text('Use Biometrics'));
    await tester.pump();
    expect(prompts, 2);
    await completeAuthentication(tester, true);
    expect(container.read(securityControllerProvider).isLocked, false);
    await unmount(tester);
  });

  testWidgets('unavailable biometrics leave PIN fallback usable',
      (tester) async {
    available = false;
    await tester
        .runAsync(() => security.setLockEnabled(true, pinOrPattern: '1234'));
    await mount(tester);
    await lifecycle(tester);
    expect(prompts, 0);
    expect(container.read(securityControllerProvider).isLocked, true);
    tester.widget<PinPad>(find.byType(PinPad)).onCompleted('1234');
    await tester.pumpAndSettle();
    expect(container.read(securityControllerProvider).isLocked, false);
    await unmount(tester);
  });

  testWidgets('concurrent app and vault requests share cancellation',
      (tester) async {
    final app = security.authenticateBiometric();
    final vault = security.authenticateBiometric();
    expect(identical(app, vault), true);
    await tester.pump();
    expect(prompts, 1);
    expect(options.single['stickyAuth'], false);
    expect(options.single['biometricOnly'], true);
    await completeAuthentication(tester, false);
    expect(await app, false);
    expect(await vault, false);
    expect(security.isAuthenticating, false);
    expect(container.read(securityControllerProvider).isLocked, true);
  });
}
