import 'dart:async';

import 'package:flutter/services.dart';

/// MediaStore is only a source of candidates, not a complete PDF library.
/// Paths must still be checked on disk; unavailable indexing never blocks a walk.
class PdfMediaStoreIndex {
  const PdfMediaStoreIndex();

  static const channel = MethodChannel('com.arcpdf.app/pdf_index');

  Future<List<String>?> paths() async {
    try {
      final result = await channel
          .invokeMethod<Object?>('listPdfPaths')
          .timeout(const Duration(seconds: 3));
      if (result is! List || result.any((path) => path is! String)) return null;
      return result.cast<String>();
    } on TimeoutException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
