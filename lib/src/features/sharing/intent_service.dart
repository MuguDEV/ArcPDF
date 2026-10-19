import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../pdf/application/pdf_library_controller.dart';
import '../pdf/domain/pdf_file_item.dart';
import '../pdf/viewer/pdf_viewer_screen.dart';
import '../navigation/navigation_controller.dart';

final intentServiceProvider = Provider<IntentService>((ref) {
  final service = IntentService(ref);
  ref.onDispose(service.dispose);
  ref.listen<bool>(splashDoneProvider, (prev, isDone) {
    if (isDone && !service.splashCompleter.isCompleted) {
      service.splashCompleter.complete();
    }
  });
  return service;
});

class IntentService {
  IntentService(this.ref, {Widget Function(PdfFileItem)? viewerBuilder})
      : _viewerBuilder = viewerBuilder ?? _defaultViewer {
    if (ref.read(splashDoneProvider)) splashCompleter.complete();
  }

  static Widget _defaultViewer(PdfFileItem item) => PdfViewerScreen(item: item);

  final Ref ref;
  final Widget Function(PdfFileItem) _viewerBuilder;
  StreamSubscription<List<SharedMediaFile>>? _intentDataStreamSubscription;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Completer<void> splashCompleter = Completer<void>();
  final Set<String> _pendingPaths = {};
  Future<void> _pendingIntent = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;

  void init() {
    if (_initialized || _disposed) return;
    _initialized = true;
    final receiver = ReceiveSharingIntent.instance;
    try {
      _intentDataStreamSubscription = receiver.getMediaStream().listen(
            _handleSharedFiles,
            onError: (Object _) => debugPrint('Incoming file stream failed.'),
          );
    } catch (_) {
      debugPrint('Incoming file stream is unavailable.');
    }
    unawaited(_loadInitialMedia(receiver));
  }

  Future<void> _loadInitialMedia(ReceiveSharingIntent receiver) async {
    try {
      final files = await receiver.getInitialMedia();
      if (_disposed) return;
      _handleSharedFiles(files);
      if (files.isNotEmpty) await receiver.reset();
    } catch (_) {
      debugPrint('Initial incoming files could not be loaded or reset.');
    }
  }

  String? _localPath(SharedMediaFile media) {
    if (media.type != SharedMediaType.file) return null;
    try {
      var path = media.path;
      if (path.toLowerCase().startsWith('file:')) {
        path = Uri.parse(path).toFilePath(windows: Platform.isWindows);
      }
      // A content:// URI must be resolved by the native plugin, not treated
      // as a local path. Never fetch incoming URLs or open relative paths.
      if (!p.isAbsolute(path) || path.contains('\u0000')) return null;
      if (!path.toLowerCase().endsWith('.pdf') &&
          media.mimeType?.toLowerCase() != 'application/pdf') {
        return null;
      }
      return p.normalize(path);
    } catch (_) {
      return null;
    }
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (_disposed) return;
    final paths = <String>[];
    for (final media in files) {
      final path = _localPath(media);
      if (path != null && _pendingPaths.add(path)) paths.add(path);
    }
    if (paths.isEmpty) return;
    _pendingIntent = _pendingIntent.then((_) async {
      try {
        if (!_disposed) await _openFirstValidPdf(paths);
      } catch (_) {
        // Plugin/filesystem/navigation failures must not escape an unawaited
        // stream callback or poison the queue for subsequent incoming files.
        debugPrint('Incoming PDF could not be opened.');
      } finally {
        _pendingPaths.removeAll(paths);
      }
    });
  }

  Future<PdfFileItem?> _readPdf(String path) async {
    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final file = File(path);
      final handle = await file.open();
      try {
        if (String.fromCharCodes(await handle.read(5)) != '%PDF-') return null;
      } finally {
        await handle.close();
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return PdfFileItem(
        path: path,
        name: p.basename(path),
        sizeBytes: stat.size,
        lastModified: stat.modified,
        locationLabel: p.basename(p.dirname(path)),
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _openFirstValidPdf(List<String> paths) async {
    PdfFileItem? item;
    for (final path in paths) {
      if (_disposed) return;
      item = await _readPdf(path);
      if (item != null) break;
    }
    if (item == null || _disposed) return;
    await splashCompleter.future;
    if (_disposed) return;

    // The key belongs to the root Navigator: its context has no Navigator
    // ancestor. Use the NavigatorState directly, after its first frame.
    NavigatorState? navigator;
    for (var attempt = 0; attempt < 30 && !_disposed; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      navigator = navigatorKey.currentState;
      if (navigator != null && navigator.mounted) break;
    }
    if (_disposed || navigator == null || !navigator.mounted) return;
    try {
      await ref.read(pdfLibraryControllerProvider.notifier).markRecent(item);
    } catch (_) {
      debugPrint('Incoming PDF recent history could not be saved.');
    }
    if (_disposed || !navigator.mounted) return;
    unawaited(navigator.push<void>(MaterialPageRoute<void>(
      builder: (_) => _viewerBuilder(item!),
    )));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _intentDataStreamSubscription?.cancel();
    if (!splashCompleter.isCompleted) splashCompleter.complete();
    _pendingPaths.clear();
  }
}
