import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:arcpdf/src/features/vault/vault_controller.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:arcpdf/src/features/vault/vault_init_exception.dart';

class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('arcpdf_test');
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

// Track flutter_secure_storage reads
class MockFlutterSecureStorage extends FlutterSecureStorage {
  static int readCount = 0;
  static Map<String, String> mockValues = {};

  const MockFlutterSecureStorage();

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    readCount++;
    return mockValues[key];
  }

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value != null) mockValues[key] = value;
  }
}

void main() {
  late ProviderContainer container;
  late FakePathProviderPlatform fakePathProvider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    MockFlutterSecureStorage.mockValues = {};
    MockFlutterSecureStorage.readCount = 0;
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

  test('moveToVault called immediately after construction (the race)', () async {
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
  });

  test('corrupt/null secure storage -> VaultInitException', () async {
    FlutterSecureStorage.setMockInitialValues({'vault_key': 'invalid_len'});

    final controller = container.read(vaultControllerProvider.notifier);

    final dummyFile = File('${fakePathProvider.tempDir.path}/dummy3.pdf');
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    await expectLater(controller.moveToVault(item), throwsA(isA<VaultInitException>()));

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
