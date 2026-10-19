import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path/path.dart' as p;
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
  Completer<void>? documentsGate;
  Completer<void>? temporaryGate;
  Completer<void>? temporaryRequested;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    getAppDocPathCallCount++;
    await documentsGate?.future;
    return tempDir.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    temporaryRequested?.complete();
    await temporaryGate?.future;
    return tempDir.path;
  }
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

    final dummyFile = File(p.join(fakePathProvider.tempDir.path, 'dummy.pdf'));
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final result = await controller.moveToVault(item);
    expect(result, isTrue);
  });

  test('concurrent ready calls share initialization', () async {
    fakePathProvider.documentsGate = Completer<void>();
    final controller = container.read(vaultControllerProvider.notifier);
    final first = controller.ready;
    final second = controller.ready;
    fakePathProvider.documentsGate!.complete();
    await Future.wait([first, second]);
    expect(fakePathProvider.getAppDocPathCallCount, 1);
  });

  test('locked restore cannot race with an import', () async {
    final controller = container.read(vaultControllerProvider.notifier);

    final dummyFile = File(p.join(fakePathProvider.tempDir.path, 'dummy2.pdf'));
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final results = await Future.wait([
      controller.moveToVault(item),
      controller.restoreFromVault(item, fakePathProvider.tempDir.path),
    ]);

    expect(results, [true, false]);

    // _initVault calls getApplicationDocumentsDirectory() exactly once.
    // By tracking how many times the path provider was queried, we assert init only ran once
    // despite two concurrent entries into `ready`.
    expect(fakePathProvider.getAppDocPathCallCount, 1);
  });

  test('corrupt storage fails; empty vault can retry after storage repair',
      () async {
    FlutterSecureStorage.setMockInitialValues({'vault_key': 'invalid_len'});

    final controller = container.read(vaultControllerProvider.notifier);

    final dummyFile = File(p.join(fakePathProvider.tempDir.path, 'dummy3.pdf'));
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

    final dummyFile = File(p.join(fakePathProvider.tempDir.path, 'dummy4.pdf'));
    dummyFile.writeAsBytesSync([1, 2, 3, 4]);
    final item = PdfFileItem.fromFile(dummyFile);

    final result = await controller.moveToVault(item);
    expect(result, isTrue);
  });

  for (final missing in ['vault_key', 'vault_iv', 'both']) {
    test('missing $missing never regenerates over existing ciphertext',
        () async {
      final stored = <String, String>{
        'vault_key': base64Encode(List.filled(32, 7)),
        'vault_iv': base64Encode(List.filled(16, 8)),
      };
      if (missing == 'both') {
        stored.clear();
      } else {
        stored.remove(missing);
      }
      FlutterSecureStorage.setMockInitialValues(Map.of(stored));
      final vault = Directory(p.join(fakePathProvider.tempDir.path, 'vault'));
      vault.createSync();
      final ciphertext = File(p.join(vault.path, 'existing.pdf'));
      ciphertext.writeAsBytesSync([9, 8, 7, 6]);
      final controller = container.read(vaultControllerProvider.notifier);
      await expectLater(controller.ready, throwsA(isA<VaultInitException>()));
      expect(await const FlutterSecureStorage().readAll(), stored);
      expect(ciphertext.readAsBytesSync(), [9, 8, 7, 6]);
      final source = File(p.join(fakePathProvider.tempDir.path, 'new.pdf'));
      source.writeAsBytesSync([1, 2, 3]);
      await expectLater(controller.moveToVault(PdfFileItem.fromFile(source)),
          throwsA(isA<VaultInitException>()));
      expect(source.readAsBytesSync(), [1, 2, 3]);
      expect(ciphertext.readAsBytesSync(), [9, 8, 7, 6]);
      expect(await const FlutterSecureStorage().readAll(), stored);
    });
  }

  for (final credential in ['vault_key', 'vault_iv']) {
    for (final invalid in [
      'not-base64!',
      base64Encode([1, 2])
    ]) {
      test('invalid $credential never modifies secure storage: $invalid',
          () async {
        final stored = {credential: invalid};
        FlutterSecureStorage.setMockInitialValues(Map.of(stored));
        final controller = container.read(vaultControllerProvider.notifier);
        await expectLater(controller.ready, throwsA(isA<VaultInitException>()));
        expect(await const FlutterSecureStorage().readAll(), stored);
      });
    }
  }

  test('unlock during cold start loads existing files after initialization',
      () async {
    final vault = Directory(p.join(fakePathProvider.tempDir.path, 'vault'));
    vault.createSync();
    File(p.join(vault.path, 'existing.pdf')).writeAsBytesSync([1]);
    FlutterSecureStorage.setMockInitialValues({
      'vault_key': base64Encode(List.filled(32, 7)),
      'vault_iv': base64Encode(List.filled(16, 8)),
    });
    fakePathProvider.documentsGate = Completer<void>();
    final controller = container.read(vaultControllerProvider.notifier);
    controller.setUnlocked(true);
    fakePathProvider.documentsGate!.complete();
    await controller.ready;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(vaultControllerProvider).vaultFiles.single.name,
        'existing.pdf');
  });

  test('locking during initialization does not publish files later', () async {
    fakePathProvider.documentsGate = Completer<void>();
    final controller = container.read(vaultControllerProvider.notifier);
    controller.setUnlocked(true);
    controller.setUnlocked(false);
    fakePathProvider.documentsGate!.complete();
    await controller.ready;
    await Future<void>.delayed(Duration.zero);
    final state = container.read(vaultControllerProvider);
    expect(state.isUnlocked, false);
    expect(state.isLoading, false);
    expect(state.vaultFiles, isEmpty);
  });

  test('locked vault hides names and rejects decrypt and restore', () async {
    final source = File(p.join(fakePathProvider.tempDir.path, 'private.pdf'));
    source.writeAsBytesSync([1, 2, 3, 4]);
    final controller = container.read(vaultControllerProvider.notifier);
    expect(await controller.moveToVault(PdfFileItem.fromFile(source)), true);
    final encrypted =
        File(p.join(fakePathProvider.tempDir.path, 'vault', 'private.pdf'));
    final item = PdfFileItem.fromFile(encrypted, isEncrypted: true);
    expect(container.read(vaultControllerProvider).vaultFiles, isEmpty);
    expect(await controller.decryptToTempFile(item), isNull);
    expect(
        await controller.restoreFromVault(item, fakePathProvider.tempDir.path),
        false);
    expect(encrypted.existsSync(), true);
    expect(source.existsSync(), false);
  });

  test('restore preserves an existing destination file', () async {
    final source = File(p.join(fakePathProvider.tempDir.path, 'private.pdf'));
    source.writeAsBytesSync([1, 2, 3, 4]);
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.moveToVault(PdfFileItem.fromFile(source));
    controller.setUnlocked(true);
    await controller.loadVaultFiles();
    final item = container.read(vaultControllerProvider).vaultFiles.single;
    source.writeAsBytesSync([99]);
    expect(
        await controller.restoreFromVault(item, fakePathProvider.tempDir.path),
        true);
    expect(source.readAsBytesSync(), [99]);
    expect(
        File(p.join(fakePathProvider.tempDir.path, 'private_1.pdf'))
            .readAsBytesSync(),
        [1, 2, 3, 4]);
  });

  test('preview is revoked if locked while waiting for temporary storage',
      () async {
    final source = File(p.join(fakePathProvider.tempDir.path, 'private.pdf'));
    source.writeAsBytesSync([1, 2, 3]);
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.moveToVault(PdfFileItem.fromFile(source));
    controller.setUnlocked(true);
    await controller.loadVaultFiles();
    final item = container.read(vaultControllerProvider).vaultFiles.single;
    fakePathProvider.temporaryGate = Completer<void>();
    fakePathProvider.temporaryRequested = Completer<void>();
    final preview = controller.decryptToTempFile(item);
    await fakePathProvider.temporaryRequested!.future;
    controller.setUnlocked(false);
    fakePathProvider.temporaryGate!.complete();
    expect(await preview, isNull);
    expect(
        fakePathProvider.tempDir
            .listSync()
            .whereType<Directory>()
            .where((dir) => p.basename(dir.path).startsWith('arcpdf_vault_')),
        isEmpty);
  });

  test('unlocked operations reject external files and restore into vault',
      () async {
    final source = File(p.join(fakePathProvider.tempDir.path, 'private.pdf'));
    source.writeAsBytesSync([1, 2, 3]);
    final controller = container.read(vaultControllerProvider.notifier);
    controller.setUnlocked(true);
    await controller.ready;
    final external = PdfFileItem.fromFile(source);
    expect(await controller.decryptToTempFile(external), isNull);
    expect(
        await controller.restoreFromVault(
            external, fakePathProvider.tempDir.path),
        false);
    expect(await controller.moveToVault(external), true);
    final item = container.read(vaultControllerProvider).vaultFiles.single;
    final ciphertext = File(item.path).readAsBytesSync();
    expect(await controller.moveToVault(item), false);
    expect(
        await controller.restoreFromVault(item, p.dirname(item.path)), false);
    expect(File(item.path).readAsBytesSync(), ciphertext);
  });

  test('repeated previews use independent temporary files', () async {
    final source = File(p.join(fakePathProvider.tempDir.path, 'private.pdf'));
    source.writeAsBytesSync([1, 2, 3]);
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.moveToVault(PdfFileItem.fromFile(source));
    controller.setUnlocked(true);
    await controller.loadVaultFiles();
    final item = container.read(vaultControllerProvider).vaultFiles.single;
    final first = await controller.decryptToTempFile(item);
    final second = await controller.decryptToTempFile(item);
    expect(first!.path, isNot(second!.path));
    first.parent.deleteSync(recursive: true);
    expect(second.readAsBytesSync(), [1, 2, 3]);
  });

  test('initialization failure is visible, not reported as an empty vault',
      () async {
    FlutterSecureStorage.setMockInitialValues({'vault_key': 'invalid!'});
    final controller = container.read(vaultControllerProvider.notifier);
    controller.setUnlocked(true);
    await controller.loadVaultFiles();
    final state = container.read(vaultControllerProvider);
    expect(state.hasError, true);
    expect(state.isLoading, false);
    expect(state.vaultFiles, isEmpty);
  });

  test('concurrent imports with identical names retain both documents',
      () async {
    final controller = container.read(vaultControllerProvider.notifier);
    final sources = <PdfFileItem>[];
    for (var i = 0; i < 2; i++) {
      final dir = Directory(p.join(fakePathProvider.tempDir.path, 'source$i'));
      dir.createSync();
      final file = File(p.join(dir.path, 'same.pdf'));
      file.writeAsBytesSync([i + 1]);
      sources.add(PdfFileItem.fromFile(file));
    }
    expect(
        await Future.wait(sources.map(controller.moveToVault)), [true, true]);
    controller.setUnlocked(true);
    await controller.loadVaultFiles();
    final files = container.read(vaultControllerProvider).vaultFiles;
    expect(files, hasLength(2));
    final contents = <List<int>>[];
    for (final item in files) {
      final temp = await controller.decryptToTempFile(item);
      contents.add(await temp!.readAsBytes());
    }
    expect(
        contents,
        unorderedEquals([
          [1],
          [2]
        ]));
  });
}
