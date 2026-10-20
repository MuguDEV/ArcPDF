import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_media_store_index.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class LocalPathProvider extends PathProviderPlatform {
  LocalPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'private_temp');

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');
}

class IndexedTestScanner extends PdfScannerService {
  IndexedTestScanner(this.root,
      {this.permission = StoragePermissionStatus.granted});
  final String root;
  final StoragePermissionStatus permission;
  int walks = 0;
  Future<void>? walkGate;
  Future<List<String>?>? indexResponse;
  final walkStarted = Completer<void>();

  @override
  Future<ScanResult> scanDirectories(List<String> roots,
      {List<String> excludedRoots = const []}) async {
    if (!walkStarted.isCompleted) walkStarted.complete();
    if (walkGate != null) await walkGate;
    return super.scanDirectories(roots, excludedRoots: excludedRoots);
  }

  @override
  Future<StoragePermissionStatus> requestPermission(
          {bool request = true}) async =>
      permission;

  @override
  Future<List<String>> discoveryRoots() async {
    walks++;
    return [root];
  }

  @override
  Future<List<String>> excludedRoots() async => [
        p.join(root, 'vault'),
        p.join(root, 'private_temp'),
        p.join(root, 'support'),
      ];

  @override
  Future<List<String>?> indexedPaths() =>
      indexResponse ?? const PdfMediaStoreIndex().paths();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  const scanner = PdfScannerService();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_scan_');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(PdfMediaStoreIndex.channel, null);
    await directory.delete(recursive: true);
  });

  Future<File> write(String relative, String content) async {
    final file = File(p.join(directory.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  test('index candidates are validated early, then full walk replaces them',
      () async {
    final indexed = await write('indexed.pdf', '%PDF-1.7\nbody');
    final unindexed = await write('unindexed.pdf', '%PDF-1.7\nbody');
    final stale = await write('stale.pdf', '%PDF-1.7\nbody');
    final fake = await write('fake.pdf', 'not a PDF');
    final vault =
        await write(p.join('vault', 'secret.pdf'), '%PDF-1.7\nplaintext');
    final temp = await write(
        p.join('private_temp', 'preview.pdf'), '%PDF-1.7\nplaintext');
    final support =
        await write(p.join('support', 'working.pdf'), '%PDF-1.7\nbody');
    final external = await write(
        p.join('Android', 'data', 'app', 'private.pdf'), '%PDF-1.7\nbody');
    await stale.delete();
    messenger.setMockMethodCallHandler(PdfMediaStoreIndex.channel,
        (call) async {
      expect(call.method, 'listPdfPaths');
      return [
        indexed.path,
        indexed.path,
        stale.path,
        fake.path,
        vault.path,
        temp.path,
        support.path,
        external.path,
        'relative.pdf'
      ];
    });
    final walkGate = Completer<void>();
    final indexedScanner = IndexedTestScanner(directory.path)
      ..walkGate = walkGate.future;
    var publications = 0;
    final finalResult = await indexedScanner.scan(onIndexed: (result) async {
      publications++;
      expect(indexedScanner.walks, 1);
      expect(result.files.map((file) => file.path), [indexed.path]);
      // Do not retain indexed files that disappear during reconciliation.
      await indexed.delete();
      walkGate.complete();
    });
    expect(publications, 1);
    expect(indexedScanner.walks, 1);
    expect(finalResult.files.map((file) => file.path), [unindexed.path]);
  });

  for (final failure in ['missing', 'error', 'malformed', 'empty']) {
    test('index $failure still performs comprehensive filesystem discovery',
        () async {
      final file = await write('unindexed.pdf', '%PDF-1.7\nbody');
      messenger.setMockMethodCallHandler(PdfMediaStoreIndex.channel,
          (call) async {
        switch (failure) {
          case 'missing':
            throw MissingPluginException();
          case 'error':
            throw PlatformException(code: 'index_unavailable');
          case 'malformed':
            return [42];
          default:
            return <String>[];
        }
      });
      final walkGate = Completer<void>();
      final indexedScanner = IndexedTestScanner(directory.path)
        ..walkGate = failure == 'empty' ? walkGate.future : null;
      var publications = 0;
      final result = await indexedScanner.scan(onIndexed: (_) async {
        publications++;
        walkGate.complete();
      });
      expect(result.files.map((item) => item.path), [file.path]);
      expect(indexedScanner.walks, 1);
      expect(publications, failure == 'empty' ? 1 : 0);
    });
  }

  test('denied permission invokes neither index nor filesystem walk', () async {
    var indexCalls = 0;
    messenger.setMockMethodCallHandler(PdfMediaStoreIndex.channel, (_) async {
      indexCalls++;
      return [];
    });
    final indexedScanner = IndexedTestScanner(directory.path,
        permission: StoragePermissionStatus.denied);
    final result = await indexedScanner.scan(
        onIndexed: (_) async => fail('must not publish'));
    expect(result.permissionStatus, StoragePermissionStatus.denied);
    expect(result.files, isEmpty);
    expect(indexCalls, 0);
    expect(indexedScanner.walks, 0);
  });

  test('repeated indexed discovery revalidates replaced and deleted files',
      () async {
    final file = await write('indexed.pdf', '%PDF-1.7\nbody');
    messenger.setMockMethodCallHandler(
        PdfMediaStoreIndex.channel, (_) async => [file.path]);
    final indexedScanner = IndexedTestScanner(directory.path);
    final publications = <List<String>>[];
    Future<void> scanWithIndexFirst() async {
      final walkGate = Completer<void>();
      indexedScanner.walkGate = walkGate.future;
      await indexedScanner.scan(onIndexed: (result) async {
        publications.add(result.files.map((item) => item.path).toList());
        walkGate.complete();
      });
    }

    await scanWithIndexFirst();
    await file.writeAsString('vault ciphertext');
    await scanWithIndexFirst();
    await file.delete();
    await scanWithIndexFirst();
    expect(publications, [
      [file.path],
      <String>[],
      <String>[]
    ]);
  });

  test('held index does not delay full scan and cannot publish late', () async {
    final file = await write('unindexed.pdf', '%PDF-1.7\nbody');
    final response = Completer<Object?>();
    final indexEntered = Completer<void>();
    messenger.setMockMethodCallHandler(PdfMediaStoreIndex.channel, (_) {
      indexEntered.complete();
      return response.future;
    });
    final indexedScanner = IndexedTestScanner(directory.path);
    final publications = <ScanResult>[];
    final scan = indexedScanner.scan(onIndexed: (result) async {
      publications.add(result);
    });
    await indexEntered.future;
    await indexedScanner.walkStarted.future;
    final full = await scan.timeout(const Duration(seconds: 2));
    expect(response.isCompleted, isFalse);
    expect(full.files.map((item) => item.path), [file.path]);
    response.complete([file.path]);
    // Drain the late channel reply; no validation/publication may follow it.
    await Future<void>.delayed(Duration.zero);
    expect(publications, isEmpty);
  });

  test('late index errors are observed after the full scan wins', () async {
    final file = await write('unindexed.pdf', '%PDF-1.7\nbody');
    final response = Completer<List<String>?>();
    final indexedScanner = IndexedTestScanner(directory.path)
      ..indexResponse = response.future;
    final full =
        await indexedScanner.scan(onIndexed: (_) async => fail('late index'));
    expect(full.files.map((item) => item.path), [file.path]);
    response.completeError(StateError('late index failure'));
    await Future<void>.delayed(Duration.zero);
    // flutter_test also fails this test if the detached branch leaks the error.
  });

  test('full failure closes index publication and observes its late error',
      () async {
    final response = Completer<List<String>?>();
    final gate = Completer<void>();
    final indexedScanner = IndexedTestScanner(directory.path)
      ..indexResponse = response.future
      ..walkGate = gate.future;
    final scan =
        indexedScanner.scan(onIndexed: (_) async => fail('late index'));
    final failed = expectLater(scan, throwsA(isA<FileSystemException>()));
    await indexedScanner.walkStarted.future;
    gate.completeError(const FileSystemException('walk failed'));
    await failed;
    response.completeError(StateError('late index failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('full completion does not wait for a held index callback', () async {
    final file = await write('indexed.pdf', '%PDF-1.7\nbody');
    final gate = Completer<void>();
    final entered = Completer<void>();
    final callback = Completer<void>();
    final indexedScanner = IndexedTestScanner(directory.path)
      ..indexResponse = Future.value([file.path])
      ..walkGate = gate.future;
    final scan = indexedScanner.scan(onIndexed: (_) {
      entered.complete();
      return callback.future;
    });
    await entered.future;
    gate.complete();
    final full = await scan;
    expect(full.files.map((item) => item.path), [file.path]);
    expect(callback.isCompleted, isFalse);
    callback.completeError(StateError('late callback failure'));
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('unresponsive index times out instead of blocking discovery',
      (tester) async {
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(
        PdfMediaStoreIndex.channel, (_) => response.future);
    final result = const PdfMediaStoreIndex().paths();
    await tester.pump(const Duration(seconds: 3));
    expect(await result, isNull);
    response.complete(<String>[]);
    await tester.pump();
  });

  test('walk excludes trashed and pending PDFs as well as private roots',
      () async {
    final visible = await write('visible.pdf', '%PDF-1.7\nbody');
    for (final name in [
      '.trashed-123-old.pdf',
      '.pending-123-new.pdf',
      p.join('.Trash', 'removed.pdf'),
      p.join('Android', 'obb', 'app', 'private.pdf'),
      p.join('vault', 'plaintext.pdf'),
      p.join('private_temp', 'preview.pdf'),
    ]) {
      await write(name, '%PDF-1.7\nbody');
    }
    final result = await scanner.scanDirectories([
      directory.path
    ], excludedRoots: [
      p.join(directory.path, 'vault'),
      p.join(directory.path, 'private_temp')
    ]);
    expect(result.files.map((file) => file.path), [visible.path]);
  });

  test('non-Android discovery does not call Android-only external storage APIs',
      () async {
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = LocalPathProvider(directory.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    final file = await write('discovered.pdf', '%PDF-1.7\nbody');
    final result = await scanner.scan();
    expect(result.files.map((item) => item.path), [file.path]);
  }, skip: Platform.isAndroid);

  test('scans nested PDFs once across duplicate and overlapping roots',
      () async {
    final a = await write('a.PDF', '%PDF-1.7\nbody');
    final b = await write(p.join('nested', 'b.pdf'), '%PDF-1.4\nbody');
    final result = await scanner.scanDirectories([
      directory.path,
      directory.path,
      p.join(directory.path, 'nested'),
      p.join(directory.path, 'nested', '..'),
    ]);
    expect(result.permissionStatus, StoragePermissionStatus.granted);
    expect(result.files.map((file) => p.normalize(file.path)),
        unorderedEquals([a.path, b.path]));
  });

  test(
      'ignores non-PDF content, empty files, other extensions and missing roots',
      () async {
    final valid = await write('valid.pdf', '%PDF-1.7\nbody');
    await write('empty.pdf', '');
    await write('short.pdf', '%PDF');
    await write('fake.pdf', 'this is not a PDF');
    await write('other.txt', '%PDF-1.7\nbody');
    final result = await scanner.scanDirectories([
      p.join(directory.path, 'missing'),
      directory.path,
    ]);
    expect(result.files.map((file) => file.path), [valid.path]);
  });

  test('detects encryption markers at either end and sorts newest first',
      () async {
    final old = await write('old.pdf', '%PDF-1.7\n/Encrypt 1 0 R');
    final recent =
        await write('recent.pdf', '%PDF-1.7\n${'x' * 9000}/Encrypt 2 0 R');
    final plain = await write('plain.pdf', '%PDF-1.7\nplain');
    await old.setLastModified(DateTime(2020));
    await plain.setLastModified(DateTime(2021));
    await recent.setLastModified(DateTime(2022));
    final result = await scanner.scanDirectories([directory.path]);
    expect(result.files.map((file) => file.name),
        ['recent.pdf', 'plain.pdf', 'old.pdf']);
    expect(result.files.map((file) => file.isEncrypted), [true, false, true]);
  });

  test('fresh scans reconcile renamed, deleted and changed PDFs', () async {
    final renamed = await write('old.pdf', '%PDF-1.7\nbody');
    final deleted = await write('deleted.pdf', '%PDF-1.7\nbody');
    final changed = await write('changed.pdf', '%PDF-1.7\nbody');
    final invalidated = await write('invalidated.pdf', '%PDF-1.7\nbody');
    expect(
        (await scanner.scanDirectories([directory.path])).files, hasLength(4));

    final newPath = p.join(directory.path, 'new.pdf');
    await renamed.rename(newPath);
    await deleted.delete();
    await changed.writeAsString('%PDF-1.7\n${'x' * 9000}/Encrypt 1 0 R');
    await changed.setLastModified(DateTime(2024));
    // Vault ciphertext retains the .pdf extension but not the PDF header.
    await invalidated.writeAsString('encrypted vault bytes');
    final result = await scanner.scanDirectories([directory.path]);
    expect(result.files.map((file) => file.path),
        unorderedEquals([newPath, changed.path]));
    final updated =
        result.files.singleWhere((file) => file.path == changed.path);
    expect(updated.isEncrypted, isTrue);
    expect(updated.sizeBytes, await changed.length());
    expect(updated.lastModified, (await changed.stat()).modified);
  });

  test('accepts minimum headers and detects markers across the tail window',
      () async {
    final minimal = await write('minimal.pdf', '%PDF-');
    // The marker starts just before the first 4096-byte read ends.
    final boundary =
        await write('boundary.pdf', '%PDF-${'x' * 4087}/Encrypt${'x' * 100}');
    final result = await scanner.scanDirectories([directory.path]);
    expect(result.files.map((file) => file.path),
        unorderedEquals([minimal.path, boundary.path]));
    expect(
        result.files
            .singleWhere((file) => file.path == minimal.path)
            .isEncrypted,
        isFalse);
    expect(
        result.files
            .singleWhere((file) => file.path == boundary.path)
            .isEncrypted,
        isTrue);
  });

  test('does not follow symlink files, directories or cycles', () async {
    await write('valid.pdf', '%PDF-1.7\nbody');
    final outside = await Directory.systemTemp.createTemp('arcpdf_outside_');
    addTearDown(() => outside.delete(recursive: true));
    final external = await File(p.join(outside.path, 'private.pdf'))
        .writeAsString('%PDF-1.7');
    await Link(p.join(directory.path, 'alias.pdf')).create(external.path);
    await Link(p.join(directory.path, 'external')).create(outside.path);
    await Link(p.join(directory.path, 'cycle')).create(directory.path);
    final result = await scanner.scanDirectories([directory.path]);
    expect(result.files.map((file) => file.name), ['valid.pdf']);
    final linkedRoot =
        await scanner.scanDirectories([p.join(directory.path, 'external')]);
    expect(linkedRoot.files, isEmpty);
  },
      skip: Platform.isWindows
          ? 'Windows symlink creation requires Developer Mode or elevation'
          : false);
}
