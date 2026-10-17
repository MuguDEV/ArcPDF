import 'package:flutter_test/flutter_test.dart';
import 'package:arcpdf/src/core/utils/logger.dart';

void main() {
  group('LogEntry', () {
    test('toMap and fromMap full round trip', () {
      final now = DateTime.now();
      final entry = LogEntry(
        timestamp: now,
        level: 'INFO',
        message: 'A test message',
        stackTrace: 'Some stack trace',
      );

      final map = entry.toMap();
      final decoded = LogEntry.fromMap(map);

      expect(decoded.timestamp, entry.timestamp);
      expect(decoded.level, 'INFO');
      expect(decoded.message, 'A test message');
      expect(decoded.stackTrace, 'Some stack trace');
    });

    test('toMap and fromMap with null stackTrace', () {
      final now = DateTime.now();
      final entry = LogEntry(
        timestamp: now,
        level: 'WARNING',
        message: 'No stack trace here',
      );

      final map = entry.toMap();
      final decoded = LogEntry.fromMap(map);

      expect(decoded.timestamp, entry.timestamp);
      expect(decoded.level, 'WARNING');
      expect(decoded.message, 'No stack trace here');
      expect(decoded.stackTrace, isNull);
    });
  });
}
