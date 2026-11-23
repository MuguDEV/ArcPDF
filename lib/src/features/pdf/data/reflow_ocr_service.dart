import 'dart:io';

import 'package:flutter/services.dart';

class ReflowOcrService {
  ReflowOcrService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.arcpdf.app/reflow_ocr');

  final MethodChannel _channel;

  Future<List<Map<String, Object?>>> recognizePages(
    String path,
    List<int> pages,
  ) async {
    if (!Platform.isAndroid || pages.isEmpty) return const [];
    try {
      final result =
          await _channel.invokeListMethod<Object?>('recognizePages', {
        'path': path,
        'pages': pages,
        'maxDimension': 2400,
      });
      return (result ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((page) => page.map(
                (key, value) => MapEntry(key.toString(), value),
              ))
          .cast<Map<String, Object?>>()
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      // Reflow remains useful for mixed/native-text documents when OCR is not
      // available on a specific device or the scanned page is unreadable.
      return const [];
    }
  }
}
