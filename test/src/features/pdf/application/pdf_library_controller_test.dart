import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hive/hive.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'dart:io';

class MockPdfScannerService extends Mock implements PdfScannerService {}

class MockBox<T> extends Mock implements Box<T> {}

void main() {
  group('PdfLibraryController filteredItems', () {
    late MockPdfScannerService mockScanner;
    late MockBox<String> mockFavBox;
    late MockBox<String> mockRecentsBox;
    late MockBox<int> mockTimestampsBox;
    late MockBox<List<String>> mockTagsBox;
    late PdfLibraryController controller;

    setUp(() {
      mockScanner = MockPdfScannerService();
      mockFavBox = MockBox<String>();
      mockRecentsBox = MockBox<String>();
      mockTimestampsBox = MockBox<int>();
      mockTagsBox = MockBox<List<String>>();

      when(() => mockFavBox.keys).thenReturn([]);
      when(() => mockRecentsBox.keys).thenReturn([]);
      when(() => mockTagsBox.keys).thenReturn([]);
      when(() => mockFavBox.values).thenReturn([]);
      when(() => mockRecentsBox.values).thenReturn([]);
      when(() => mockTimestampsBox.toMap()).thenReturn({});
      when(() => mockFavBox.delete(any())).thenAnswer((_) async {});
      when(() => mockRecentsBox.delete(any())).thenAnswer((_) async {});
      when(() => mockTimestampsBox.delete(any())).thenAnswer((_) async {});
      when(() => mockTagsBox.delete(any())).thenAnswer((_) async {});

      controller = PdfLibraryController(
        mockScanner,
        mockFavBox,
        mockRecentsBox,
        mockTimestampsBox,
        mockTagsBox,
      );
    });

    tearDown(() => controller.dispose());

    test('filters items correctly based on query and filter', () {
      final now = DateTime.now();
      final item1 = PdfFileItem(
        path: '/test/doc.pdf',
        name: 'doc.pdf',
        sizeBytes: 1024,
        lastModified: now.subtract(const Duration(days: 1)),
        locationLabel: 'test',
      );
      final item2 = PdfFileItem(
        path: '/test/large_download.pdf',
        name: 'large_download.pdf',
        sizeBytes: 20 * 1024 * 1024, // 20 MB
        lastModified: now.subtract(const Duration(days: 10)),
        locationLabel: 'test',
      );

      // Set items directly by creating a new state
      controller.state = controller.state.copyWith(items: [item1, item2]);

      // No query, no filters -> both items
      expect(controller.filteredItems().length, 2);

      // Search by query -> "large"
      controller.setQuery('large');
      expect(controller.filteredItems().length, 1);
      expect(controller.filteredItems().first.name, 'large_download.pdf');

      // Filter by downloads
      controller.setQuery('');
      controller.setFilter(PdfFilter.downloads);
      expect(controller.filteredItems().length, 1);
      expect(controller.filteredItems().first.name, 'large_download.pdf');

      // Filter by recent (<= 7 days)
      controller.setFilter(PdfFilter.recent);
      expect(controller.filteredItems().length, 1);
      expect(controller.filteredItems().first.name, 'doc.pdf');

      // Filter by large (>= 10 MB)
      controller.setFilter(PdfFilter.large);
      expect(controller.filteredItems().length, 1);
      expect(controller.filteredItems().first.name, 'large_download.pdf');
    });

    test('keeps the chosen duplicate and removes the remaining copies once',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('arcpdf_duplicate_cleanup_');
      addTearDown(() => directory.delete(recursive: true));
      final files = [
        File('${directory.path}/first.pdf'),
        File('${directory.path}/keep.pdf'),
        File('${directory.path}/third.pdf'),
      ];
      for (final file in files) {
        await file.writeAsBytes([1, 2, 3, 4]);
      }
      final items = files.map(PdfFileItem.fromFile).toList();
      final group = PdfDuplicateGroup(
        digest: 'same-content',
        sizeBytes: 4,
        reclaimableBytes: 8,
        paths: files.map((file) => file.path).toList(),
      );
      controller.state = controller.state.copyWith(
        items: items,
        duplicateGroups: [group],
        favorites: files.map((file) => file.path).toSet(),
      );

      final result = await controller.keepOnlyDuplicate(group, files[1].path);

      expect(result.deletedPaths, {files[0].path, files[2].path});
      expect(result.failedPaths, isEmpty);
      expect(result.reclaimedBytes, 8);
      expect(await files[1].exists(), isTrue);
      expect(await files[0].exists(), isFalse);
      expect(await files[2].exists(), isFalse);
      expect(controller.state.items.map((item) => item.path), [files[1].path]);
      expect(controller.state.duplicateGroups, isEmpty);
      expect(controller.state.favorites, {files[1].path});
    });

    test('refuses to delete a duplicate that changed after scanning', () async {
      final directory =
          await Directory.systemTemp.createTemp('arcpdf_duplicate_changed_');
      addTearDown(() => directory.delete(recursive: true));
      final keep = File('${directory.path}/keep.pdf')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final changed = File('${directory.path}/changed.pdf')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final items = [PdfFileItem.fromFile(keep), PdfFileItem.fromFile(changed)];
      final group = PdfDuplicateGroup(
        digest: 'old-match',
        sizeBytes: 4,
        reclaimableBytes: 4,
        paths: [keep.path, changed.path],
      );
      controller.state = controller.state.copyWith(
        items: items,
        duplicateGroups: [group],
      );
      await changed.writeAsBytes([9, 8, 7, 6, 5]);

      final result = await controller.keepOnlyDuplicate(group, keep.path);

      expect(result.deletedPaths, isEmpty);
      expect(result.failedPaths, {changed.path});
      expect(await changed.exists(), isTrue);
      expect(controller.state.duplicateGroups, [group]);
    });
  });
}
