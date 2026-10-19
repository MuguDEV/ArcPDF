import 'dart:async';
import 'dart:io';

import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class MockScanner extends Mock implements PdfScannerService {}

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
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) async => result([]));
    controller =
        PdfLibraryController(scanner, favorites, recents, timestamps, tags);
  });

  tearDown(() async {
    if (controller.mounted) controller.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
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
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
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
    verify(() => scanner.scan(requestPermission: true)).called(1);
  });

  test('older completion cannot clear loading for a newer pending scan',
      () async {
    final older = Completer<ScanResult>();
    final newer = Completer<ScanResult>();
    var calls = 0;
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) => calls++ == 0 ? older.future : newer.future);
    final first = controller.refresh();
    final second = controller.refresh();
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
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
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
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) => scan.future);
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
    verifyNever(
        () => scanner.scan(requestPermission: any(named: 'requestPermission')));
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
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) => scan.future);
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
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) => scan.future);
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
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
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
    verifyNever(
        () => scanner.scan(requestPermission: any(named: 'requestPermission')));
    controller =
        PdfLibraryController(scanner, favorites, recents, timestamps, tags);
    final scan = Completer<ScanResult>();
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) => scan.future);
    final refresh = controller.refresh();
    controller.dispose();
    scan.complete(result([]));
    await refresh;
  });
}
