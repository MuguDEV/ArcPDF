import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hive/hive.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';

class MockPdfScannerService extends Mock implements PdfScannerService {}
class MockBox<T> extends Mock implements Box<T> {}

void main() {
  group('PdfLibraryController filteredItems', () {
    late MockPdfScannerService mockScanner;
    late MockBox<String> mockFavBox;
    late MockBox<String> mockRecentsBox;
    late MockBox<int> mockTimestampsBox;
    late PdfLibraryController controller;

    setUp(() {
      mockScanner = MockPdfScannerService();
      mockFavBox = MockBox<String>();
      mockRecentsBox = MockBox<String>();
      mockTimestampsBox = MockBox<int>();

      when(() => mockFavBox.keys).thenReturn([]);
      when(() => mockRecentsBox.keys).thenReturn([]);
      when(() => mockFavBox.values).thenReturn([]);
      when(() => mockRecentsBox.values).thenReturn([]);

      controller = PdfLibraryController(
        mockScanner,
        mockFavBox,
        mockRecentsBox,
        mockTimestampsBox,
      );
    });

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
  });
}
