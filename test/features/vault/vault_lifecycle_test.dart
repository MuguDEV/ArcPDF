import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:hive/hive.dart';
import 'package:arcpdf/src/features/security/security_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:arcpdf/src/features/vault/vault_controller.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('arcpdf_test');
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  late ProviderContainer container;
  late FakePathProviderPlatform fakePathProvider;
  late Box settings;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;
    Hive.init(fakePathProvider.tempDir.path);
    settings = await Hive.openBox('vault_lifecycle_settings');
    container = ProviderContainer(overrides: [
      securityControllerProvider
          .overrideWith((ref) => SecurityController(settings)),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await settings.close();
    if (fakePathProvider.tempDir.existsSync()) {
      fakePathProvider.tempDir.deleteSync(recursive: true);
    }
  });

  test('unlock with correct PIN, multiple ops', () async {
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.ready;

    final security = container.read(securityControllerProvider.notifier);
    await security.setLockEnabled(true, pinOrPattern: '1234');
    expect(await security.verifyPinOrPattern('9999'), false);
    expect(container.read(vaultControllerProvider).isUnlocked, false);
    final verified = await security.verifyPinOrPattern('1234');
    expect(verified, true);
    controller.setUnlocked(verified);
    expect(container.read(vaultControllerProvider).isUnlocked, true);

    final dummyFile = File(p.join(fakePathProvider.tempDir.path, 'dummy4.pdf'));
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final res1 = await controller.moveToVault(item);
    expect(res1, true);

    // Successful operations finish updating the visible file list.
    final files = container.read(vaultControllerProvider).vaultFiles;
    expect(files.isNotEmpty, true);

    final res2 = await controller.restoreFromVault(
        files.first, fakePathProvider.tempDir.path);
    expect(res2, true);
    expect(dummyFile.readAsBytesSync(), [1, 2, 3, 4]);
    expect(container.read(vaultControllerProvider).vaultFiles, isEmpty);
  });

  test('lock, failed PIN, valid PIN and cold restart preserve encrypted data',
      () async {
    var controller = container.read(vaultControllerProvider.notifier);
    final security = container.read(securityControllerProvider.notifier);
    await security.setLockEnabled(true, pinOrPattern: '1234');
    final source = File(p.join(fakePathProvider.tempDir.path, 'private.pdf'));
    source.writeAsBytesSync([10, 20, 30]);
    expect(await controller.moveToVault(PdfFileItem.fromFile(source)), true);
    final storageBefore = await const FlutterSecureStorage().readAll();
    container.dispose();
    container = ProviderContainer(overrides: [
      securityControllerProvider
          .overrideWith((ref) => SecurityController(settings)),
    ]);
    controller = container.read(vaultControllerProvider.notifier);
    final restartedSecurity =
        container.read(securityControllerProvider.notifier);
    expect(container.read(securityControllerProvider).isLocked, true);
    expect(await restartedSecurity.verifyPinOrPattern('bad'), false);
    expect(container.read(vaultControllerProvider).vaultFiles, isEmpty);
    expect(await restartedSecurity.verifyPinOrPattern('1234'), true);
    controller.setUnlocked(true);
    await controller.loadVaultFiles();
    final item = container.read(vaultControllerProvider).vaultFiles.single;
    controller.setUnlocked(false);
    restartedSecurity.lockApp();
    expect(await controller.decryptToTempFile(item), isNull);
    expect(
        await controller.restoreFromVault(item, fakePathProvider.tempDir.path),
        false);
    expect(await restartedSecurity.verifyPinOrPattern('1234'), true);
    controller.setUnlocked(true);
    await controller.loadVaultFiles();
    final preview = await controller.decryptToTempFile(item);
    expect(preview!.readAsBytesSync(), [10, 20, 30]);
    expect(await const FlutterSecureStorage().readAll(), storageBefore);
  });

  test('changing or disabling app PIN does not rotate vault credentials',
      () async {
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.ready;
    const storage = FlutterSecureStorage();
    final key = await storage.read(key: 'vault_key');
    final iv = await storage.read(key: 'vault_iv');
    final security = container.read(securityControllerProvider.notifier);
    await security.setLockEnabled(true, pinOrPattern: '1234');
    await security.setLockEnabled(true, pinOrPattern: '5678');
    expect(await security.verifyPinOrPattern('1234'), false);
    expect(await security.verifyPinOrPattern('5678'), true);
    await security.setLockEnabled(false);
    expect(await storage.read(key: 'vault_key'), key);
    expect(await storage.read(key: 'vault_iv'), iv);
  });
}
