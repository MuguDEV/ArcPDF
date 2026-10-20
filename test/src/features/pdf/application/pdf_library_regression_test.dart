import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class MockScanner extends Mock implements PdfScannerService {}

class MockTagsBox extends Mock implements Box<List<String>> {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box<String> favorites;
  late Box<String> recents;
  late Box<int> timestamps;
  late Box<List<String>> tags;
  late MockScanner scanner;
  late PdfLibraryController controller;

  ScanResult result(List<PdfFileItem> files) => ScanResult(
      files: files, permissionStatus: StoragePermissionStatus.granted);

  Future<PdfFileItem> createPdf(String name) async {
    final file = File(p.join(directory.path, name));
    await file.writeAsString('%PDF-1.7\nbody');
    return PdfFileItem.fromFile(file);
  }

  Future<void> seedMetadata(PdfFileItem item) async {
    await controller.toggleFavorite(item);
    await controller.markRecent(item);
    await controller.addTag(item, 'Custom');
    controller.setSelectedTag('Custom');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_library_');
    Hive.init(directory.path);
    favorites = await Hive.openBox<String>('favorites');
    recents = await Hive.openBox<String>('recents');
    timestamps = await Hive.openBox<int>('timestamps');
    tags = await Hive.openBox<List<String>>('tags');
    scanner = MockScanner();
    when(() => scanner.scan(
            requestPermission: any(named: 'requestPermission'),
            onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) async => result([]));
    controller =
        PdfLibraryController(scanner, favorites, recents, timestamps, tags);
    // Explicit refresh cancels startup scheduling so each test controls scans.
    await controller.refresh();
    clearInteractions(scanner);
  });

  tearDown(() async {
    if (controller.mounted) controller.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('overlapping passive refreshes share live scan, not completed results',
      () async {
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) => scan.future);
    final first = controller.refresh();
    final second = controller.refresh();
    expect(identical(first, second), isTrue);
    verify(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).called(1);
    scan.complete(result([]));
    await Future.wait([first, second]);
    await controller.refresh();
    verify(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).called(1);
  });

  test('empty library publishes indexed items before final reconciliation',
      () async {
    final indexed = await createPdf('indexed.pdf');
    final unindexed = await createPdf('unindexed.pdf');
    final full = Completer<ScanResult>();
    final published = Completer<void>();
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((invocation) async {
      final publish = invocation.namedArguments[#onIndexed] as Future<void>
          Function(ScanResult);
      await publish(result([indexed]));
      published.complete();
      return full.future;
    });
    final refresh = controller.refresh();
    await published.future;
    expect(controller.state.items.map((file) => file.path), [indexed.path]);
    expect(controller.state.loading, isFalse);
    expect(identical(controller.refresh(), refresh), isTrue);
    full.complete(result([indexed, unindexed]));
    await refresh;
    expect(controller.state.items.map((file) => file.path),
        [indexed.path, unindexed.path]);
  });

  test('empty index keeps first-load loading until unindexed full result',
      () async {
    final unindexed = await createPdf('unindexed.pdf');
    final full = Completer<ScanResult>();
    final indexHandled = Completer<void>();
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((invocation) async {
      final publish = invocation.namedArguments[#onIndexed] as Future<void>
          Function(ScanResult);
      await publish(result([]));
      indexHandled.complete();
      return full.future;
    });
    final refresh = controller.refresh();
    await indexHandled.future;
    expect(controller.state.items, isEmpty);
    expect(controller.state.loading, isTrue);
    expect(identical(controller.refresh(), refresh), isTrue);
    full.complete(result([unindexed]));
    await refresh;
    expect(controller.state.items.map((file) => file.path), [unindexed.path]);
    expect(controller.state.loading, isFalse);
  });

  test('routine refresh keeps full items until authoritative reconciliation',
      () async {
    final indexed = await createPdf('indexed.pdf');
    final unindexed = await createPdf('unindexed.pdf');
    when(() => scanner.scan(
            requestPermission: false, onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) async => result([indexed, unindexed]));
    await controller.refresh();
    final full = Completer<ScanResult>();
    late Future<void> Function(ScanResult) publish;
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((invocation) {
      publish = invocation.namedArguments[#onIndexed] as Future<void> Function(
          ScanResult);
      return full.future;
    });
    final refresh = controller.refresh();
    await File(unindexed.path).delete();
    await publish(result([indexed]));
    // Stored state does not shrink to the index, but remains loading: unchecked
    // previous rows are not republished as a newly validated/usable library.
    expect(controller.state.items.map((file) => file.path),
        [indexed.path, unindexed.path]);
    expect(controller.state.loading, isTrue);
    full.complete(result([indexed]));
    await refresh;
    expect(controller.state.items.map((file) => file.path), [indexed.path]);
    expect(controller.state.loading, isFalse);
  });

  test('late indexed callback cannot overwrite a completed full refresh',
      () async {
    final indexed = await createPdf('indexed.pdf');
    final unindexed = await createPdf('unindexed.pdf');
    late Future<void> Function(ScanResult) publish;
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((invocation) async {
      publish = invocation.namedArguments[#onIndexed] as Future<void> Function(
          ScanResult);
      return result([indexed, unindexed]);
    });
    await controller.refresh();
    await publish(result([indexed]));
    expect(controller.state.items.map((file) => file.path),
        [indexed.path, unindexed.path]);
    expect(controller.state.loading, isFalse);
  });

  for (final mutation in ['rename', 'delete', 'vault']) {
    test('$mutation invalidates both late indexed and full publications',
        () async {
      final item = await createPdf('invoice.pdf');
      await seedMetadata(item);
      final full = Completer<ScanResult>();
      late Future<void> Function(ScanResult) publish;
      when(() => scanner.scan(
          requestPermission: false,
          onIndexed: any(named: 'onIndexed'))).thenAnswer((invocation) {
        publish = invocation.namedArguments[#onIndexed] as Future<void>
            Function(ScanResult);
        return full.future;
      });
      final refresh = controller.refresh();
      await publish(result([item]));
      switch (mutation) {
        case 'rename':
          expect(await controller.renameFile(item, 'renamed'), isTrue);
        case 'delete':
          expect(await controller.deleteFile(item), isTrue);
        case 'vault':
          await File(item.path).delete();
          expect(await controller.removeMissingFile(item), isTrue);
      }
      await publish(result([item]));
      full.complete(result([item]));
      await refresh;
      expect(
          controller.state.items.map((file) => file.path),
          mutation == 'rename'
              ? [p.join(directory.path, 'renamed.pdf')]
              : isEmpty);
      expect(tags.containsKey(item.path), isFalse);
      expect(controller.state.loading, isFalse);
    });
  }

  test('new permission refresh rejects older indexed publication', () async {
    final stale = await createPdf('invoice.pdf');
    final current = await createPdf('current.pdf');
    final older = Completer<ScanResult>();
    late Future<void> Function(ScanResult) publishOlder;
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((invocation) {
      publishOlder = invocation.namedArguments[#onIndexed] as Future<void>
          Function(ScanResult);
      return older.future;
    });
    final first = controller.refresh();
    when(() => scanner.scan(
            requestPermission: true, onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) async => result([current]));
    await controller.refresh(requestPermission: true);
    await publishOlder(result([stale]));
    older.complete(result([stale]));
    await first;
    expect(controller.state.items.single.path, current.path);
    expect(tags.containsKey(stale.path), isFalse);
  });

  test('favorite mutations do not emit UI feedback', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final item = await createPdf('favorite.pdf');
    await controller.toggleFavorite(item);
    expect(controller.state.favorites, contains(item.path));
    await controller.toggleFavorite(item);
    expect(controller.state.favorites, isNot(contains(item.path)));
    expect(calls.where((call) => call.method == 'HapticFeedback.vibrate'),
        isEmpty);
  });

  testWidgets('startup starts scanning on the next event without a fixed delay',
      (tester) async {
    controller.dispose();
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) => scan.future);
    controller =
        PdfLibraryController(scanner, favorites, recents, timestamps, tags);
    verifyNever(() => scanner.scan(
        requestPermission: false, onIndexed: any(named: 'onIndexed')));
    await tester.pump(Duration.zero);
    verify(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).called(1);
    expect(controller.state.loading, isTrue);
    scan.complete(result([]));
    await tester.pump();
    expect(controller.state.loading, isFalse);
  });

  test('publishes scanned library before slow auto-tag writes finish',
      () async {
    final item = await createPdf('invoice.pdf');
    final entered = Completer<void>();
    final saved = Completer<void>();
    final slowTags = MockTagsBox();
    when(() => slowTags.keys).thenReturn([]);
    when(() => slowTags.put(item.path, ['Invoice'])).thenAnswer((_) {
      entered.complete();
      return saved.future;
    });
    controller.dispose();
    controller =
        PdfLibraryController(scanner, favorites, recents, timestamps, slowTags);
    when(() => scanner.scan(
            requestPermission: false, onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) async => result([item]));
    final refresh = controller.refresh();
    await entered.future;
    expect(controller.state.items.single.path, item.path);
    expect(controller.state.loading, isFalse);
    expect(controller.state.tags, isEmpty);
    saved.complete();
    await refresh;
    expect(controller.state.tags[item.path], ['Invoice']);
  });

  test('late auto-tag completion cannot overwrite a newer pending refresh',
      () async {
    final older = await createPdf('invoice.pdf');
    final current = await createPdf('current.pdf');
    final entered = Completer<void>();
    final saved = Completer<void>();
    final newerScan = Completer<ScanResult>();
    final slowTags = MockTagsBox();
    when(() => slowTags.keys).thenReturn([]);
    when(() => slowTags.put(older.path, ['Invoice'])).thenAnswer((_) {
      entered.complete();
      return saved.future;
    });
    controller.dispose();
    controller =
        PdfLibraryController(scanner, favorites, recents, timestamps, slowTags);
    var calls = 0;
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) async {
      if (calls++ == 0) return result([older]);
      return newerScan.future;
    });
    final first = controller.refresh();
    await entered.future;
    final second = controller.refresh();
    saved.complete();
    await first;
    expect(controller.state.loading, isTrue);
    newerScan.complete(result([current]));
    await second;
    expect(controller.state.items.single.path, current.path);
    expect(controller.state.loading, isFalse);
    expect(controller.state.tags[older.path], ['Invoice']);
  });

  test('auto-tag failure does not prevent publishing the scanned library',
      () async {
    final item = await createPdf('invoice.pdf');
    await tags.close();
    when(() => scanner.scan(
            requestPermission: false, onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) async => result([item]));
    await controller.refresh();
    expect(controller.state.items.single.path, item.path);
    expect(controller.state.loading, isFalse);
  });

  test('vault cleanup invalidates an in-flight scan of the removed source',
      () async {
    final item = await createPdf('invoice.pdf');
    await seedMetadata(item);
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(
        requestPermission: false,
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) => scan.future);
    final refresh = controller.refresh();
    await File(item.path).delete();
    expect(await controller.removeMissingFile(item), isTrue);
    scan.complete(result([item]));
    await refresh;
    expect(controller.state.items, isEmpty);
    expect(controller.state.tags, isEmpty);
    expect(tags.containsKey(item.path), isFalse);
    expect(controller.state.loading, isFalse);
  });

  test('vault metadata cleanup never deletes a replacement source file',
      () async {
    final item = await createPdf('moved.pdf');
    await seedMetadata(item);
    expect(await controller.removeMissingFile(item), isFalse);
    expect(await File(item.path).exists(), isTrue);
    expect(controller.state.favorites, contains(item.path));
    await File(item.path).delete();
    expect(await controller.removeMissingFile(item), isTrue);
    expect(controller.state.favorites, isNot(contains(item.path)));
    expect(controller.state.recents, isNot(contains(item.path)));
    expect(controller.state.tags, isNot(contains(item.path)));
    expect(favorites.containsKey(item.path), isFalse);
  });

  test('copyWith preserves selected tag and permits explicit clearing', () {
    const original = PdfLibraryState(selectedTag: 'Custom');
    expect(original.copyWith(loading: true).selectedTag, 'Custom');
    expect(original.copyWith(selectedTag: null).selectedTag, isNull);
    controller.setSelectedTag('Custom');
    controller.setQuery('book');
    controller.setFilter(PdfFilter.large);
    controller.setSortField(PdfSortField.name);
    expect(controller.state.selectedTag, 'Custom');
    controller.setSelectedTag(null);
    expect(controller.state.selectedTag, isNull);
  });

  test('newest refresh wins and stale scan does not auto-tag', () async {
    final older = Completer<ScanResult>();
    final newer = Completer<ScanResult>();
    var calls = 0;
    when(() => scanner.scan(
            requestPermission: any(named: 'requestPermission'),
            onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) => calls++ == 0 ? older.future : newer.future);
    final stale = await createPdf('invoice.pdf');
    final current = await createPdf('current.pdf');
    final first = controller.refresh();
    final second = controller.refresh(requestPermission: true);
    newer.complete(result([current]));
    await second;
    older.complete(result([stale]));
    await first;
    expect(controller.state.items.single.path, current.path);
    expect(controller.state.loading, isFalse);
    expect(tags.containsKey(stale.path), isFalse);
    verify(() => scanner.scan(
        requestPermission: true, onIndexed: any(named: 'onIndexed'))).called(1);
  });

  test('older completion cannot clear loading for a newer pending scan',
      () async {
    final older = Completer<ScanResult>();
    final newer = Completer<ScanResult>();
    var calls = 0;
    when(() => scanner.scan(
            requestPermission: any(named: 'requestPermission'),
            onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) => calls++ == 0 ? older.future : newer.future);
    final first = controller.refresh();
    final second = controller.refresh(requestPermission: true);
    older.complete(result([]));
    await first;
    expect(controller.state.loading, isTrue);
    newer.complete(result([]));
    await second;
    expect(controller.state.loading, isFalse);
  });

  test('scan failure preserves usable items and clears loading', () async {
    final item = await createPdf('current.pdf');
    await controller.markRecent(item);
    controller.setSelectedTag('Custom');
    when(() => scanner.scan(
            requestPermission: any(named: 'requestPermission'),
            onIndexed: any(named: 'onIndexed')))
        .thenThrow(StateError('scanner unavailable'));
    await controller.refresh();
    expect(controller.state.items.single.path, item.path);
    expect(controller.state.loading, isFalse);
    expect(controller.state.selectedTag, 'Custom');
  });

  test('concurrent metadata operations do not lose changes', () async {
    final a = await createPdf('a.pdf');
    final b = await createPdf('b.pdf');
    await Future.wait([
      controller.addTag(a, 'One'),
      controller.addTag(a, 'Two'),
      controller.addTag(b, 'Three'),
      controller.toggleFavorite(a),
      controller.toggleFavorite(b),
      controller.markRecent(a),
      controller.markRecent(b),
    ]);
    expect(controller.state.tags[a.path], ['One', 'Two']);
    expect(controller.state.tags[b.path], ['Three']);
    expect(controller.state.favorites, {a.path, b.path});
    expect(controller.state.recents.keys, unorderedEquals([a.path, b.path]));
    expect(tags.get(a.path), ['One', 'Two']);
    await Future.wait([
      controller.toggleFavorite(a),
      controller.toggleFavorite(a),
    ]);
    expect(controller.state.favorites, {a.path, b.path});
    await Future.wait([controller.markRecent(a), controller.clearRecents()]);
    expect(controller.state.recents, isEmpty);
    expect(recents.isEmpty, isTrue);
    expect(timestamps.isEmpty, isTrue);
  });

  test('refresh auto-tags merge with concurrent manual edits', () async {
    final item = await createPdf('invoice.pdf');
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(
        requestPermission: any(named: 'requestPermission'),
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) => scan.future);
    final refresh = controller.refresh();
    final manual = controller.addTag(item, 'Custom');
    scan.complete(result([item]));
    await Future.wait([refresh, manual]);
    expect(
        controller.state.tags[item.path], containsAll(['Custom', 'Invoice']));
    expect(tags.get(item.path), controller.state.tags[item.path]);
  });

  test('rename migrates all persisted and live metadata without scanning',
      () async {
    final item = await createPdf('old.pdf');
    await seedMetadata(item);
    final openedAt = controller.state.recents[item.path];
    final timestamp = timestamps.get(item.path);
    final newPath = p.join(directory.path, 'renamed.PDF');
    expect(await controller.renameFile(item, 'renamed.PDF'), isTrue);
    expect(await File(item.path).exists(), isFalse);
    expect(await File(newPath).exists(), isTrue);
    expect(controller.state.items.single.path, newPath);
    expect(controller.state.items.single.name, 'renamed.PDF');
    expect(controller.state.favorites, {newPath});
    expect(controller.state.recents, {newPath: openedAt});
    expect(controller.state.tags, {
      newPath: ['Custom']
    });
    expect(controller.state.selectedTag, 'Custom');
    expect(favorites.get(newPath), newPath);
    expect(recents.get(newPath), newPath);
    expect(timestamps.get(newPath), timestamp);
    expect(tags.get(newPath), ['Custom']);
    for (final box in <Box>[favorites, recents, timestamps, tags]) {
      expect(box.containsKey(item.path), isFalse);
    }
    verifyNever(() => scanner.scan(
        requestPermission: any(named: 'requestPermission'),
        onIndexed: any(named: 'onIndexed')));
  });

  test('rename rejects traversal, invalid names and existing destinations',
      () async {
    final item = await createPdf('old.pdf');
    final existing = await createPdf('existing.pdf');
    final directoryCollision =
        await Directory(p.join(directory.path, 'folder.pdf')).create();
    for (final name in [
      '',
      ' ',
      '.',
      '..',
      '../escape',
      r'..\escape',
      '/escape',
      'bad\u0000name',
      'bad:name',
      'trailing.',
      'CON',
      'existing',
      'folder'
    ]) {
      expect(await controller.renameFile(item, name), isFalse, reason: name);
    }
    expect(await File(item.path).exists(), isTrue);
    expect(await File(existing.path).readAsString(), '%PDF-1.7\nbody');
    expect(await directoryCollision.exists(), isTrue);
    expect(await controller.renameFile(item, 'old.pdf'), isTrue);
    expect(await controller.renameFile(item, 'safe'), isTrue);
    expect(await File(p.join(directory.path, 'safe.pdf')).exists(), isTrue);
  });

  test('rename invalidates an in-flight scan of the old path', () async {
    final item = await createPdf('old.pdf');
    await seedMetadata(item);
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(
        requestPermission: any(named: 'requestPermission'),
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) => scan.future);
    final refresh = controller.refresh();
    expect(await controller.renameFile(item, 'new'), isTrue);
    scan.complete(result([item]));
    await refresh;
    expect(
        controller.state.items.single.path, p.join(directory.path, 'new.pdf'));
    expect(controller.state.loading, isFalse);
  });

  test('delete removes file and all metadata and rejects directories',
      () async {
    final item = await createPdf('delete.pdf');
    await seedMetadata(item);
    expect(await controller.deleteFile(item), isTrue);
    expect(await File(item.path).exists(), isFalse);
    expect(controller.state.items, isEmpty);
    expect(controller.state.favorites, isEmpty);
    expect(controller.state.recents, isEmpty);
    expect(controller.state.tags, isEmpty);
    for (final box in <Box>[favorites, recents, timestamps, tags]) {
      expect(box.containsKey(item.path), isFalse);
    }
    expect(await controller.deleteFile(item), isTrue);
    await Directory(item.path).create();
    expect(await controller.deleteFile(item), isFalse);
    expect(await Directory(item.path).exists(), isTrue);
  });

  test(
      'delete invalidates pending scans and clears already-missing file metadata',
      () async {
    final item = await createPdf('missing.pdf');
    await seedMetadata(item);
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(
        requestPermission: any(named: 'requestPermission'),
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) => scan.future);
    final refresh = controller.refresh();
    await File(item.path).delete();
    expect(await controller.deleteFile(item), isTrue);
    scan.complete(result([item]));
    await refresh;
    expect(controller.state.items, isEmpty);
    expect(controller.state.favorites, isEmpty);
    expect(controller.state.loading, isFalse);
  });

  test('metadata persistence failure does not misreport a successful rename',
      () async {
    final item = await createPdf('old.pdf');
    await seedMetadata(item);
    await favorites.close();
    expect(await controller.renameFile(item, 'new'), isTrue);
    expect(
        controller.state.items.single.path, p.join(directory.path, 'new.pdf'));
    expect(await File(item.path).exists(), isFalse);
  });

  test('failed metadata mutation does not poison subsequent operations',
      () async {
    final item = await createPdf('current.pdf');
    await tags.close();
    await expectLater(
        controller.addTag(item, 'Fail'), throwsA(isA<HiveError>()));
    await controller.markRecent(item);
    expect(controller.state.recents, contains(item.path));
  });

  test('permission denial never prunes saved metadata', () async {
    final item = await createPdf('saved.pdf');
    await seedMetadata(item);
    when(() => scanner.scan(
            requestPermission: any(named: 'requestPermission'),
            onIndexed: any(named: 'onIndexed')))
        .thenAnswer((_) async => const ScanResult(
            files: [], permissionStatus: StoragePermissionStatus.denied));
    await controller.refresh();
    expect(controller.state.permissionStatus, StoragePermissionStatus.denied);
    expect(controller.state.loading, isFalse);
    expect(controller.state.favorites, {item.path});
    expect(controller.state.recents, contains(item.path));
    expect(controller.state.tags[item.path], ['Custom']);
    expect(controller.state.selectedTag, 'Custom');
    expect(tags.get(item.path), ['Custom']);
  });

  test(
      'rename finishes metadata migration when disposed during filesystem work',
      () async {
    final item = await createPdf('old.pdf');
    await seedMetadata(item);
    final rename = controller.renameFile(item, 'new');
    await Future<void>.value();
    controller.dispose();
    expect(await rename, isTrue);
    final newPath = p.join(directory.path, 'new.pdf');
    expect(await File(newPath).exists(), isTrue);
    expect(favorites.get(newPath), newPath);
    expect(recents.get(newPath), newPath);
    expect(tags.get(newPath), ['Custom']);
    expect(tags.containsKey(item.path), isFalse);
  });

  test('delete finishes metadata cleanup when disposed during filesystem work',
      () async {
    final item = await createPdf('delete.pdf');
    await seedMetadata(item);
    final deletion = controller.deleteFile(item);
    await Future<void>.value();
    controller.dispose();
    expect(await deletion, isTrue);
    expect(await File(item.path).exists(), isFalse);
    for (final box in <Box>[favorites, recents, timestamps, tags]) {
      expect(box.containsKey(item.path), isFalse);
    }
  });

  test('dispose cancels delayed refresh and safely ignores a late scan',
      () async {
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    verifyNever(() => scanner.scan(
        requestPermission: any(named: 'requestPermission'),
        onIndexed: any(named: 'onIndexed')));
    controller =
        PdfLibraryController(scanner, favorites, recents, timestamps, tags);
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(
        requestPermission: any(named: 'requestPermission'),
        onIndexed: any(named: 'onIndexed'))).thenAnswer((_) => scan.future);
    final refresh = controller.refresh();
    controller.dispose();
    scan.complete(result([]));
    await refresh;
  });
}
