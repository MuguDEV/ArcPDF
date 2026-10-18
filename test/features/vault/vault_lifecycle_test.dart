import 'dart:io';
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

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    fakePathProvider = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePathProvider;
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    if (fakePathProvider.tempDir.existsSync()) {
      fakePathProvider.tempDir.deleteSync(recursive: true);
    }
  });

  test('unlock with correct PIN, multiple ops', () async {
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.ready;

    // Simulate setting unlocked
    controller.setUnlocked(true);
    expect(container.read(vaultControllerProvider).isUnlocked, true);

    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy4.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final res1 = await controller.moveToVault(item);
    expect(res1, true);

    // After move, the state vaultFiles should update since we are unlocked
    // Wait for the async loadVaultFiles() triggered internally
    await Future.delayed(const Duration(milliseconds: 50));
    final files = container.read(vaultControllerProvider).vaultFiles;
    expect(files.isNotEmpty, true);

    final res2 = await controller.restoreFromVault(
        files.first, fakePathProvider.tempDir.path);
    expect(res2, true);
  });
}
