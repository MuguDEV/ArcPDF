import 'package:flutter_test/flutter_test.dart';
import 'package:arcpdf/src/data/local_boxes.dart';

void main() {
  group('LocalBoxes', () {
    test('constants have correct string values', () {
      expect(LocalBoxes.favorites, 'favorites');
      expect(LocalBoxes.recents, 'recents');
      expect(LocalBoxes.settings, 'settings');
      expect(LocalBoxes.thumbnailCache, 'thumbnailCache');
      expect(LocalBoxes.recentsTimestamps, 'recentsTimestamps');
      expect(LocalBoxes.tags, 'tags');
      expect(LocalBoxes.sessions, 'sessions');
    });
  });
}
