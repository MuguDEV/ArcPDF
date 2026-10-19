import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/security/security_controller.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/vault/vault_controller.dart';
import 'package:arcpdf/src/features/vault/vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;

  @override
  Future<String?> getTemporaryPath() async => root.path;
}

class _Security extends SecurityController {
  _Security(super.settings);

  Completer<bool> authentication = Completer<bool>();

  @override
  Future<bool> authenticateBiometric() => authentication.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Box settings;
  late ProviderContainer container;
  late _Security security;
  late VaultController vault;
  late PathProviderPlatform originalPaths;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('arcpdf_vault_screen_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root);
    FlutterSecureStorage.setMockInitialValues({});
    Hive.init(root.path);
    settings = await Hive.openBox('vault_screen_settings');
    await settings.putAll({
      'isLockEnabled': true,
      'isBiometricEnabled': true,
      'lowPowerMode': true,
      'useHaptics': false,
    });
    security = _Security(settings);
    container = ProviderContainer(overrides: [
      securityControllerProvider.overrideWith((ref) => security),
      settingsControllerProvider
          .overrideWith((ref) => SettingsController(settings)),
    ]);
    vault = container.read(vaultControllerProvider.notifier);
    final source = File(p.join(root.path, 'secret.pdf'));
    source.writeAsBytesSync([1, 2, 3]);
    expect(await vault.moveToVault(PdfFileItem.fromFile(source)), true);
  });

  tearDown(() async {
    container.dispose();
    await settings.close();
    PathProviderPlatform.instance = originalPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<GlobalKey<NavigatorState>> mount(WidgetTester tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    ));

    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const VaultScreen(),
    ));

    await tester.pump();

    return navigator;
  }

  testWidgets('stale unlocked state is hidden until fresh authentication',
      (tester) async {
    await tester.runAsync(() async {
      vault.setUnlocked(true);
      await vault.loadVaultFiles();
    });
    expect(container.read(vaultControllerProvider).vaultFiles, hasLength(1));
    await mount(tester);

    expect(find.text('secret.pdf'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('secret.pdf'), findsNothing);
    await tester.runAsync(() async {
      security.authentication.complete(true);
      await Future<void>.delayed(Duration.zero);
      await vault.loadVaultFiles();
    });
    await tester.pumpAndSettle();
    expect(find.text('secret.pdf'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('system back locks vault and clears file names', (tester) async {
    final navigator = await mount(tester);
    await tester.runAsync(() async {
      security.authentication.complete(true);
      await Future<void>.delayed(Duration.zero);
      await vault.loadVaultFiles();
    });
    await tester.pumpAndSettle();
    expect(container.read(vaultControllerProvider).isUnlocked, true);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(container.read(vaultControllerProvider).isUnlocked, false);
    expect(container.read(vaultControllerProvider).vaultFiles, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late biometric completion cannot unlock a disposed route',
      (tester) async {
    final navigator = await mount(tester);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    security.authentication.complete(true);
    await tester.pump();
    expect(container.read(vaultControllerProvider).isUnlocked, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disabled app lock never exposes a previous vault session',
      (tester) async {
    await tester.runAsync(() async {
      await security.setLockEnabled(false);
      vault.setUnlocked(true);
      await vault.loadVaultFiles();
    });
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('App Lock Required'), findsOneWidget);
    expect(find.text('secret.pdf'), findsNothing);
    expect(container.read(vaultControllerProvider).isUnlocked, false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
