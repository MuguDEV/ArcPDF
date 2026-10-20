import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/utils/logger.dart';

class PdfThumbnailCache {
  static final _memCache = <(String, bool), ui.Image>{};
  static const int _maxMemCacheSize = 100;
  static String? _cacheDir;

  static final Queue<_ThumbnailTask> _taskQueue = Queue<_ThumbnailTask>();
  static final Map<(String, bool), Future<ui.Image?>> _inFlight = {};
  static int _activeTasks = 0;
  static const int _maxConcurrentTasks = 4;

  static Future<String> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    final dir = await getApplicationSupportDirectory();
    final thumbDir = Directory('${dir.path}/thumbnails');
    await thumbDir.create(recursive: true);
    _cacheDir = thumbDir.path;
    return _cacheDir!;
  }

  static String _key(String path) => path.hashCode.toString();

  static ui.Image? getCached(String pdfPath, {bool lowPowerMode = false}) {
    final key = (pdfPath, lowPowerMode);
    final image = _memCache.remove(key);
    if (image != null) _memCache[key] = image;
    return image;
  }

  static void _addToMemCache(String path, bool lowPowerMode, ui.Image image) {
    final key = (path, lowPowerMode);
    _memCache.remove(key);
    _memCache[key] = image;
    if (_memCache.length > _maxMemCacheSize) {
      // RawImage widgets may still be using evicted images; do not dispose them.
      _memCache.remove(_memCache.keys.first);
    }
  }

  static Future<ui.Image?> getThumbnail(String pdfPath,
      {bool lowPowerMode = false}) {
    final cached = getCached(pdfPath, lowPowerMode: lowPowerMode);
    if (cached != null) return Future.value(cached);

    final key = (pdfPath, lowPowerMode);
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final completer = Completer<ui.Image?>();
    _inFlight[key] = completer.future;
    _taskQueue.add(_ThumbnailTask(pdfPath, lowPowerMode, completer));
    _processQueue();
    return completer.future;
  }

  static void _processQueue() {
    while (_activeTasks < _maxConcurrentTasks && _taskQueue.isNotEmpty) {
      _activeTasks++;
      unawaited(_runTask(_taskQueue.removeFirst()));
    }
  }

  static Future<void> _runTask(_ThumbnailTask task) async {
    ui.Image? result;
    try {
      result = await _generateThumbnail(task.pdfPath, task.lowPowerMode);
    } catch (e, stackTrace) {
      final name = task.pdfPath.split(RegExp(r'[/\\]')).last;
      AppLogger.error('Failed to generate thumbnail for $name', e, stackTrace);
    } finally {
      _inFlight.remove((task.pdfPath, task.lowPowerMode));
      _activeTasks--;
      task.completer.complete(result);
      _processQueue();
    }
  }

  static Future<ui.Image?> _generateThumbnail(
      String pdfPath, bool lowPowerMode) async {
    // Missing sources must not resurrect an orphaned disk thumbnail.
    if (!await File(pdfPath).exists()) return null;

    // 180px covers a 52dp tile at 3x without rendering a full-size preview.
    final targetWidth = lowPowerMode ? 150 : 180;
    File? file;
    try {
      file = File('${await _dir}/${_key(pdfPath)}.png');
      if (await file.exists()) {
        final codec = await ui.instantiateImageCodec(
          await file.readAsBytes(),
          targetWidth: targetWidth,
          allowUpscaling: false,
        );
        try {
          final image = (await codec.getNextFrame()).image;
          _addToMemCache(pdfPath, lowPowerMode, image);
          return image;
        } finally {
          codec.dispose();
        }
      }
    } catch (_) {
      // Disk caching is optional: unreadable/corrupt entries can be regenerated.
    }

    final trace =
        kDebugMode ? (TimelineTask()..start('PdfThumbnailCache.decode')) : null;
    PdfDocument? doc;
    PdfImage? pdfImage;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      if (doc.pages.isEmpty) return null;

      final page = doc.pages.first;
      final scale = (targetWidth / page.width).clamp(0.0, 2.0);
      pdfImage = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (pdfImage == null) return null;

      final image = await pdfImage.createImage();
      _addToMemCache(pdfPath, lowPowerMode, image);
      if (file != null) unawaited(_writeThumbnail(file, image));
      return image;
    } finally {
      try {
        pdfImage?.dispose();
      } finally {
        try {
          await doc?.dispose();
        } finally {
          trace?.finish();
        }
      }
    }
  }

  static Future<void> _writeThumbnail(File file, ui.Image image) async {
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        await file.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      }
    } catch (_) {
      // Encoding and disk writes are best-effort, including their async errors.
    }
  }
}

class _ThumbnailTask {
  final String pdfPath;
  final bool lowPowerMode;
  final Completer<ui.Image?> completer;

  _ThumbnailTask(this.pdfPath, this.lowPowerMode, this.completer);
}
