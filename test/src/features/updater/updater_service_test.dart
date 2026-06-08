import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:arcpdf/src/features/updater/updater_service.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException("Mocked network error");
  }
}

void main() {
  group('UpdaterService', () {
    test('checkForUpdates returns null on error', () async {
      HttpOverrides.global = MyHttpOverrides();

      final result = await UpdaterService.checkForUpdates();

      expect(result, isNull);

      HttpOverrides.global = null;
    });
  });
}
