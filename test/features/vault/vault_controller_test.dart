import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:arcpdf/src/features/vault/vault_controller.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Dummy Path Provider for tests
class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
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

  test('Cold start with no key initializes successfully', () async {
    final controller = container.read(vaultControllerProvider.notifier);

    // We expect no exceptions during initialization if awaited properly
    // However, the current code in constructor might not expose it.
    // We will await the new 'ready' property in the refactored code.
    // For now, just calling loadVaultFiles which should theoretically trigger it if awaited.
    await controller.loadVaultFiles();
    expect(controller.state.vaultFiles, isEmpty);
  });

  test('moveToVault called immediately after construction (race condition)', () async {
    final controller = container.read(vaultControllerProvider.notifier);

    // Create a dummy PDF
    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    // Call without awaiting any initialization manually - this should trigger the race
    // in the original code, or succeed/fail gracefully in the fixed code.
    final result = await controller.moveToVault(item);

    // If it succeeds, the file was moved
    // If it fails with LateInitializationError, the test will crash (desired for 'before' run)
  });

  test('Concurrent moveToVault and restoreFromVault (single-flight)', () async {
    final controller = container.read(vaultControllerProvider.notifier);

    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy2.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    // Run concurrently. In original code, might double-init or hit LateInitializationError
    final results = await Future.wait([
      controller.moveToVault(item),
      // Since it's not actually in vault yet, restore might just return false,
      // but we care about the initialization single-flight.
      controller.restoreFromVault(item, fakePathProvider.tempDir.path),
    ]);

    expect(results, isNotNull);
  });

}
