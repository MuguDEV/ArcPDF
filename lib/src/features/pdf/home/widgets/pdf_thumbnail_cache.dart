import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/utils/logger.dart';

import 'dart:async';
import 'dart:collection';

class PdfThumbnailCache {
  static final LinkedHashMap<String, ui.Image> _memCache = LinkedHashMap<String, ui.Image>();
  static const int _maxMemCacheSize = 100;
  static String? _cacheDir;

  static final Queue<_ThumbnailTask> _taskQueue = Queue<_ThumbnailTask>();
  static int _activeTasks = 0;
  static const int _maxConcurrentTasks = 4;

  static Future<String> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    final dir = await getApplicationSupportDirectory();
    final thumbDir = Directory('${dir.path}/thumbnails');
    if (!thumbDir.existsSync()) thumbDir.createSync();
    _cacheDir = thumbDir.path;
    return _cacheDir!;
  }

  static String _key(String path) => path.hashCode.toString();

  static ui.Image? getCached(String pdfPath) {
    if (_memCache.containsKey(pdfPath)) {
      // Move to end (most recently used)
      final val = _memCache.remove(pdfPath)!;
      _memCache[pdfPath] = val;
      return val;
    }
    return null;
  }

  static void _addToMemCache(String path, ui.Image image) {
    if (_memCache.containsKey(path)) {
      _memCache.remove(path); // Remove so it gets added to the end (most recent)
    }
    _memCache[path] = image;

    if (_memCache.length > _maxMemCacheSize) {
      // Remove least recently used (first element in LinkedHashMap)
      final firstKey = _memCache.keys.first;
      _memCache.remove(firstKey);
      // We don't forcefully call dispose() on the ui.Image because a RawImage widget
      // may still be actively attached to it in the widget tree, which will crash the app.
    }
  }

  static Future<ui.Image?> getThumbnail(String pdfPath, {bool lowPowerMode = false}) async {
    final cached = getCached(pdfPath);
    if (cached != null) return cached;

    final completer = Completer<ui.Image?>();
    _taskQueue.add(_ThumbnailTask(pdfPath, lowPowerMode, completer));
    _processQueue();

    return completer.future;
  }

  static void _processQueue() async {
    if (_activeTasks >= _maxConcurrentTasks || _taskQueue.isEmpty) return;

    _activeTasks++;
    final task = _taskQueue.removeFirst();

    try {
      final result = await _generateThumbnail(task.pdfPath, task.lowPowerMode);
      task.completer.complete(result);
    } catch (e) {
      task.completer.complete(null);
    } finally {
      _activeTasks--;
      _processQueue();
    }
  }

  static Future<ui.Image?> _generateThumbnail(String pdfPath, bool lowPowerMode) async {
    // Check cache again in case another task already generated it
    final cached = getCached(pdfPath);
    if (cached != null) return cached;

    final key = _key(pdfPath);
    final dir = await _dir;
    final file = File('$dir/$key.png');

    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      _addToMemCache(pdfPath, image);
      return image;
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

        _addToMemCache(pdfPath, image);

        // Async write bytes to disk without blocking UI texture memory load
        image.toByteData(format: ui.ImageByteFormat.png).then((byteData) {
           if (byteData != null) {
              file.writeAsBytes(byteData.buffer.asUint8List());
           }
        });

        return image;
      }
    } catch (e, stackTrace) {
      final redactedPath = pdfPath.split('/').lastOrNull ?? 'unknown_file';
      AppLogger.error('Failed to generate thumbnail for $redactedPath', e, stackTrace);
    }
    return null;
  }
}

class _ThumbnailTask {
  final String pdfPath;
  final bool lowPowerMode;
  final Completer<ui.Image?> completer;

  _ThumbnailTask(this.pdfPath, this.lowPowerMode, this.completer);
}
