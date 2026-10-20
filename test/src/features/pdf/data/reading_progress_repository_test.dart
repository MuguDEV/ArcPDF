import 'dart:io';

import 'package:arcpdf/src/data/local_boxes.dart';
import 'package:arcpdf/src/features/pdf/data/reading_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late ReadingProgressRepository repository;

  Future<void> openBoxes() async {
    await Hive.openBox<int>('reading_progress_pages');
    await Hive.openBox<double>('reading_progress_zoom');
    await Hive.openBox<int>('reading_progress_time');
    await Hive.openBox<dynamic>(LocalBoxes.sessions);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_progress_test');
    Hive.init(directory.path);
    await openBoxes();
    repository = ReadingProgressRepository();
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('page, zoom, page count and position survive closing and reopening',
      () async {
    const viewport =
        ReadingViewport(page: 12, pageCount: 12, zoom: 1.75, x: 0.42, y: 0.73);
    await repository.saveViewport('/book.pdf', viewport);
    await Hive.close();
    await openBoxes();
    repository = ReadingProgressRepository();

    expect(repository.getLastReadPage('/book.pdf'), 12);
    expect(repository.getLastZoom('/book.pdf'), 1.75);
    expect(repository.getLastViewport('/book.pdf')!.matches(viewport), isTrue);
    // A completed document keeps its last page instead of restarting at one.
    expect(repository.getLastViewport('/book.pdf')!.pageCount, 12);
    expect(repository.getLastReadPage('/other.pdf'), 1);
    expect(repository.getLastViewport('/other.pdf'), isNull);
  });

  test('a tab reopened before disk writes finish sees the latest checkpoint',
      () async {
    const viewport =
        ReadingViewport(page: 4, pageCount: 8, zoom: 2, x: 0.5, y: 0.6);
    final saving = repository.saveViewport('/book.pdf', viewport);
    expect(repository.getLastReadPage('/book.pdf'), 4);
    expect(repository.getLastZoom('/book.pdf'), 2);
    expect(repository.getLastViewport('/book.pdf')!.matches(viewport), isTrue);
    await saving;
  });

  test('legacy page and zoom work without a viewport checkpoint', () async {
    await repository.saveLastReadPage('/book.pdf', 9);
    await repository.saveLastZoom('/book.pdf', 2);
    expect(repository.getLastReadPage('/book.pdf'), 9);
    expect(repository.getLastZoom('/book.pdf'), 2);
    expect(repository.getLastViewport('/book.pdf'), isNull);
  });

  test('invalid page and zoom values are ignored on write and read', () async {
    for (final page in [0, -3]) {
      await repository.saveLastReadPage('/book.pdf', page);
      expect(repository.getLastReadPage('/book.pdf'), 1);
      await Hive.box<int>('reading_progress_pages').put('/book.pdf', page);
      expect(repository.getLastReadPage('/book.pdf'), 1);
    }
    for (final zoom in [0.0, -1.0, double.nan, double.infinity]) {
      await repository.saveLastZoom('/book.pdf', zoom);
      expect(repository.getLastZoom('/book.pdf'), isNull);
      await Hive.box<double>('reading_progress_zoom').put('/book.pdf', zoom);
      expect(repository.getLastZoom('/book.pdf'), isNull);
    }
  });

  test('malformed, unsupported and non-finite viewport data is ignored',
      () async {
    await repository.saveLastReadPage('/book.pdf', 2);
    await repository.saveLastZoom('/book.pdf', 1.5);
    final valid = <String, dynamic>{
      'version': 1,
      'page': 2,
      'pageCount': 8,
      'zoom': 1.5,
      'x': 0.5,
      'y': 0.7,
    };
    for (final value in [
      'broken',
      <String, dynamic>{},
      {...valid, 'version': 2},
      {...valid, 'page': '2'},
      {...valid, 'page': 0},
      {...valid, 'pageCount': 1},
      {...valid, 'zoom': double.infinity},
      {...valid, 'x': double.nan},
      {...valid, 'y': 'bad'},
    ]) {
      await Hive.box<dynamic>(LocalBoxes.sessions)
          .put('readingViewport:/book.pdf', value);
      expect(repository.getLastViewport('/book.pdf'), isNull);
    }
  });

  test('legacy updates invalidate stale viewport offsets', () async {
    const viewport =
        ReadingViewport(page: 2, pageCount: 8, zoom: 1.5, x: 0.5, y: 0.7);
    await repository.saveViewport('/book.pdf', viewport);
    await repository.saveLastReadPage('/book.pdf', 3);
    expect(repository.getLastViewport('/book.pdf'), isNull);
    await repository.saveViewport('/book.pdf', viewport);
    await repository.saveLastZoom('/book.pdf', 2);
    expect(repository.getLastViewport('/book.pdf'), isNull);
  });

  test('invalid snapshots never replace a usable checkpoint', () async {
    const viewport =
        ReadingViewport(page: 2, pageCount: 8, zoom: 1.5, x: 0.5, y: 0.7);
    await repository.saveViewport('/book.pdf', viewport);
    await repository.saveViewport('/book.pdf',
        const ReadingViewport(page: 9, pageCount: 8, zoom: 2, x: 0.5, y: 0.7));
    expect(repository.getLastViewport('/book.pdf')!.matches(viewport), isTrue);
  });
}
