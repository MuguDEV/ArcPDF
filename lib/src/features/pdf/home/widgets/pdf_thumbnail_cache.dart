import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/utils/logger.dart';

class PdfThumbnailCache {
  static const _decodeTimeout = Duration(seconds: 12);
  static final _memCache = <(String, bool, String), ui.Image>{};
  static const int _maxMemCacheSize = 100;
  static String? _cacheDir;

  static final Queue<_ThumbnailTask> _taskQueue = Queue<_ThumbnailTask>();
  static final Map<(String, bool, String), Future<ui.Image?>> _inFlight = {};
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

  static String _key(String path, String version) =>
      sha256.convert(utf8.encode('$path\u0000$version')).toString();

  static ui.Image? getCached(String pdfPath,
      {bool lowPowerMode = false, String cacheVersion = ''}) {
    final key = (pdfPath, lowPowerMode, cacheVersion);
    final image = _memCache.remove(key);
    if (image != null) _memCache[key] = image;
    return image?.clone();
  }

  static ui.Image? _peekCached(
      String path, bool lowPowerMode, String cacheVersion) {
    final key = (path, lowPowerMode, cacheVersion);
    final image = _memCache.remove(key);
    if (image != null) _memCache[key] = image;
    return image;
  }

  static void _addToMemCache(
      String path, bool lowPowerMode, String cacheVersion, ui.Image image) {
    final key = (path, lowPowerMode, cacheVersion);
    final previous = _memCache.remove(key);
    if (previous != null && !identical(previous, image)) previous.dispose();
    _memCache[key] = image;
    if (_memCache.length > _maxMemCacheSize) {
      final evicted = _memCache.remove(_memCache.keys.first);
      evicted?.dispose();
    }
  }

  static Future<ui.Image?> getThumbnail(String pdfPath,
      {bool lowPowerMode = false, String cacheVersion = ''}) {
    final cached = _peekCached(pdfPath, lowPowerMode, cacheVersion);
    if (cached != null) return Future.value(cached.clone());

    final key = (pdfPath, lowPowerMode, cacheVersion);
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight.then((image) => image?.clone());

    final completer = Completer<ui.Image?>();
    _inFlight[key] = completer.future;
    _taskQueue
        .add(_ThumbnailTask(pdfPath, lowPowerMode, cacheVersion, completer));
    _processQueue();
    return completer.future.then((image) => image?.clone());
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
      result = await _generateThumbnail(
          task.pdfPath, task.lowPowerMode, task.cacheVersion);
    } catch (e, stackTrace) {
      final name = task.pdfPath.split(RegExp(r'[/\\]')).last;
      AppLogger.error('Failed to generate thumbnail for $name', e, stackTrace);
    } finally {
      _inFlight.remove((task.pdfPath, task.lowPowerMode, task.cacheVersion));
      _activeTasks--;
      task.completer.complete(result);
      _processQueue();
    }
  }

  static Future<ui.Image?> _generateThumbnail(
      String pdfPath, bool lowPowerMode, String cacheVersion) async {
    // Missing sources must not resurrect an orphaned disk thumbnail.
    if (!await File(pdfPath).exists()) return null;

    // 180px covers a 52dp tile at 3x without rendering a full-size preview.
    final targetWidth = lowPowerMode ? 150 : 180;
    File? file;
    try {
      file = File('${await _dir}/${_key(pdfPath, cacheVersion)}.png');
      if (await file.exists()) {
        final codec = await ui
            .instantiateImageCodec(
              await file.readAsBytes(),
              targetWidth: targetWidth,
              allowUpscaling: false,
            )
            .timeout(_decodeTimeout);
        try {
          final image = (await codec.getNextFrame()).image;
          _addToMemCache(pdfPath, lowPowerMode, cacheVersion, image);
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
      doc = await PdfDocument.openFile(pdfPath).timeout(_decodeTimeout);
      if (doc.pages.isEmpty) return null;

      final page = doc.pages.first;
      final scale = (targetWidth / page.width).clamp(0.0, 2.0);
      pdfImage = await page
          .render(
            fullWidth: page.width * scale,
            fullHeight: page.height * scale,
          )
          .timeout(_decodeTimeout);
      if (pdfImage == null) return null;

      final image = await pdfImage.createImage();
      _addToMemCache(pdfPath, lowPowerMode, cacheVersion, image);
      if (file != null) {
        final diskImage = image.clone();
        unawaited(_writeThumbnail(file, diskImage));
      }
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
    } finally {
      image.dispose();
    }
  }
}

class _ThumbnailTask {
  final String pdfPath;
  final bool lowPowerMode;
  final String cacheVersion;
  final Completer<ui.Image?> completer;

  _ThumbnailTask(
      this.pdfPath, this.lowPowerMode, this.cacheVersion, this.completer);
}
