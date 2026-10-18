import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:arcpdf/src/features/vault/vault_controller.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:arcpdf/src/features/vault/vault_init_exception.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('arcpdf_test');
  int getAppDocPathCallCount = 0;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    getAppDocPathCallCount++;
    return tempDir.path;
  }

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

  test('moveToVault called immediately after construction (the race)',
      () async {
    final controller = container.read(vaultControllerProvider.notifier);

    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final result = await controller.moveToVault(item);
    expect(result, isTrue);
  });

  test('concurrent moveToVault + restoreFromVault (single-flight)', () async {
    final controller = container.read(vaultControllerProvider.notifier);

    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy2.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final results = await Future.wait([
      controller.moveToVault(item),
      controller.restoreFromVault(item, fakePathProvider.tempDir.path),
    ]);

    expect(results, isNotNull);

    // _initVault calls getApplicationDocumentsDirectory() exactly once.
    // By tracking how many times the path provider was queried, we assert init only ran once
    // despite two concurrent entries into `ready`.
    expect(fakePathProvider.getAppDocPathCallCount, 1);
  });

  test('corrupt/null secure storage -> VaultInitException', () async {
    FlutterSecureStorage.setMockInitialValues({'vault_key': 'invalid_len'});

    final controller = container.read(vaultControllerProvider.notifier);

    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy3.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    await expectLater(
        controller.moveToVault(item), throwsA(isA<VaultInitException>()));

    FlutterSecureStorage.setMockInitialValues({});

    final result = await controller.moveToVault(item);
    expect(result, isTrue);
  });

  test('cold start with no key initializes successfully', () async {
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.ready;

    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy4.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final result = await controller.moveToVault(item);
    expect(result, isTrue);
  });
}
