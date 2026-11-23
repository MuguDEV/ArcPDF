import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/local_boxes.dart';

/// A page-relative viewport remains useful across screen sizes and layouts.
class ReadingViewport {
  const ReadingViewport({
    required this.page,
    required this.pageCount,
    required this.zoom,
    required this.x,
    required this.y,
  });

  final int page;
  final int pageCount;
  final double zoom;
  final double x;
  final double y;

  bool get isValid =>
      page > 0 &&
      pageCount >= page &&
      zoom.isFinite &&
      zoom > 0 &&
      x.isFinite &&
      y.isFinite;

  bool matches(ReadingViewport? other) =>
      other != null &&
      page == other.page &&
      pageCount == other.pageCount &&
      zoom == other.zoom &&
      (x - other.x).abs() < 0.000001 &&
      (y - other.y).abs() < 0.000001;
}

final readingProgressRepositoryProvider =
    Provider<ReadingProgressRepository>((ref) => ReadingProgressRepository());

class ReadingProgressRepository {
  Box<int> get _pageBox => Hive.box<int>('reading_progress_pages');
  Box<double> get _zoomBox => Hive.box<double>('reading_progress_zoom');
  Box<int> get _timeBox => Hive.box<int>('reading_progress_time');

  int getLastReadPage(String pdfPath) {
    final page = _pageBox.get(pdfPath) ?? 1;
    return page > 0 ? page : 1;
  }

  Future<void> saveLastReadPage(String pdfPath, int page) async {
    if (page < 1) return;
    await _pageBox.put(pdfPath, page);
  }

  double? getLastZoom(String pdfPath) {
    final zoom = _zoomBox.get(pdfPath);
    return zoom != null && zoom.isFinite && zoom > 0 ? zoom : null;
  }

  Future<void> saveLastZoom(String pdfPath, double zoom) async {
    if (!zoom.isFinite || zoom <= 0) return;
    await _zoomBox.put(pdfPath, zoom);
  }

  ReadingViewport? getLastViewport(String pdfPath) {
    final value =
        Hive.box<dynamic>(LocalBoxes.sessions).get('readingViewport:$pdfPath');
    if (value is! Map || value['version'] != 1) return null;
    final page = value['page'];
    final count = value['pageCount'];
    final zoom = value['zoom'];
    final x = value['x'];
    final y = value['y'];
    if (page is! int ||
        count is! int ||
        zoom is! num ||
        x is! num ||
        y is! num) {
      return null;
    }
    final viewport = ReadingViewport(
      page: page,
      pageCount: count,
      zoom: zoom.toDouble(),
      x: x.toDouble(),
      y: y.toDouble(),
    );
    // Legacy page/zoom writers must not leave an obsolete position attached to
    // a newer checkpoint. A changed document is checked by the reader at load.
    return viewport.isValid &&
            viewport.page == getLastReadPage(pdfPath) &&
            viewport.zoom == getLastZoom(pdfPath)
        ? viewport
        : null;
  }

  Future<void> saveViewport(String pdfPath, ReadingViewport viewport) async {
    if (!viewport.isValid) return;
    // Start all writes together so a tab reopened in the same frame sees the
    // checkpoint immediately (Hive updates its in-memory values synchronously).
    await Future.wait([
      saveLastReadPage(pdfPath, viewport.page),
      saveLastZoom(pdfPath, viewport.zoom),
      Hive.box<dynamic>(LocalBoxes.sessions).put('readingViewport:$pdfPath', {
        'version': 1,
        'page': viewport.page,
        'pageCount': viewport.pageCount,
        'zoom': viewport.zoom,
        'x': viewport.x,
        'y': viewport.y,
      }),
    ]);
  }

  int getTotalReadTime(String pdfPath) {
    return _timeBox.get(pdfPath) ?? 0;
  }

  Future<void> addReadTime(String pdfPath, int seconds) async {
    final current = getTotalReadTime(pdfPath);
    await _timeBox.put(pdfPath, current + seconds);
  }

  /// Bookmarks are kept in the local session box so they survive reader tabs
  /// and do not modify the source PDF. The map format is deliberately simple
  /// to keep older Hive installations forward compatible.
  List<ReadingBookmark> getBookmarks(String pdfPath) {
    final raw =
        Hive.box<dynamic>(LocalBoxes.sessions).get('readerBookmarks:$pdfPath');
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(ReadingBookmark.fromMap).where((bookmark) {
      return bookmark.page > 0;
    }).toList(growable: false);
  }

  Future<void> saveBookmarks(
      String pdfPath, List<ReadingBookmark> bookmarks) async {
    await Hive.box<dynamic>(LocalBoxes.sessions).put(
      'readerBookmarks:$pdfPath',
      bookmarks.map((bookmark) => bookmark.toMap()).toList(growable: false),
    );
  }

  Future<void> migratePath(String oldPath, String newPath) async {
    final sessions = Hive.box<dynamic>(LocalBoxes.sessions);
    final viewport = sessions.get('readingViewport:$oldPath');
    final bookmarks = sessions.get('readerBookmarks:$oldPath');
    await Future.wait([
      if (_pageBox.containsKey(oldPath))
        _pageBox.put(newPath, _pageBox.get(oldPath)!),
      if (_zoomBox.containsKey(oldPath))
        _zoomBox.put(newPath, _zoomBox.get(oldPath)!),
      if (_timeBox.containsKey(oldPath))
        _timeBox.put(newPath, _timeBox.get(oldPath)!),
      if (viewport != null) sessions.put('readingViewport:$newPath', viewport),
      if (bookmarks != null)
        sessions.put('readerBookmarks:$newPath', bookmarks),
      _pageBox.delete(oldPath),
      _zoomBox.delete(oldPath),
      _timeBox.delete(oldPath),
      sessions.delete('readingViewport:$oldPath'),
      sessions.delete('readerBookmarks:$oldPath'),
    ]);
  }

  Future<void> removePath(String pdfPath) async {
    await Future.wait([
      _pageBox.delete(pdfPath),
      _zoomBox.delete(pdfPath),
      _timeBox.delete(pdfPath),
      Hive.box<dynamic>(LocalBoxes.sessions).delete('readingViewport:$pdfPath'),
      Hive.box<dynamic>(LocalBoxes.sessions).delete('readerBookmarks:$pdfPath'),
    ]);
  }
}

class ReadingBookmark {
  const ReadingBookmark({
    required this.id,
    required this.page,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final int page;
  final String label;
  final DateTime createdAt;

  factory ReadingBookmark.fromMap(Map value) {
    return ReadingBookmark(
      id: value['id']?.toString() ?? '',
      page: value['page'] is num ? (value['page'] as num).toInt() : 1,
      label: value['label']?.toString() ?? 'Page bookmark',
      createdAt: DateTime.tryParse(value['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, Object> toMap() => {
        'id': id,
        'page': page,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
      };
}
