import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/utils/logger.dart';

import 'dart:collection';

class PdfThumbnailCache {
  static final _memCache = LinkedHashMap<String, Uint8List>();
  static const int _maxMemCacheSize = 100;
  static String? _cacheDir;

  static Future<String> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    final dir = await getApplicationSupportDirectory();
    final thumbDir = Directory('${dir.path}/thumbnails');
    if (!thumbDir.existsSync()) thumbDir.createSync();
    _cacheDir = thumbDir.path;
    return _cacheDir!;
  }

  static String _key(String path) => path.hashCode.toString();

  static Uint8List? getCached(String pdfPath) {
    if (_memCache.containsKey(pdfPath)) {
      // Move to end (most recently used)
      final val = _memCache.remove(pdfPath)!;
      _memCache[pdfPath] = val;
      return val;
    }
    return null;
  }

  static void _addToMemCache(String path, Uint8List bytes) {
    if (_memCache.length >= _maxMemCacheSize) {
      // Remove first (least recently used)
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[path] = bytes;
  }

  static Future<Uint8List?> getThumbnail(String pdfPath, {bool lowPowerMode = false}) async {
    final cached = getCached(pdfPath);
    if (cached != null) return cached;

    final key = _key(pdfPath);
    final dir = await _dir;
    final file = File('$dir/$key.png');

    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      _addToMemCache(pdfPath, bytes);
      return bytes;
    }

    try {
      final doc = await PdfDocument.openFile(pdfPath);
      if (doc.pages.isEmpty) {
        doc.dispose();
        return null;
      }
      
      final page = doc.pages.first;
      
      // Render small thumbnail (e.g. max width 400)
      final double targetWidth = lowPowerMode ? 150.0 : 400.0;
      double scale = targetWidth / page.width;
      if (scale > 2.0) scale = 2.0;

      final pdfImage = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      
      doc.dispose();

      if (pdfImage != null) {
        final image = await pdfImage.createImage();
        pdfImage.dispose();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final bytes = byteData.buffer.asUint8List();
          // Write asynchronously so we don't block
          file.writeAsBytes(bytes);
          _addToMemCache(pdfPath, bytes);
          return bytes;
        }
      }
    } catch (e, stackTrace) {
      final redactedPath = pdfPath.split('/').lastOrNull ?? 'unknown_file';
      AppLogger.error('Failed to generate thumbnail for $redactedPath', e, stackTrace);
    }
    return null;
  }
}
