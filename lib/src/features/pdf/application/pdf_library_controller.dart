import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'dart:io';

import '../../../data/local_boxes.dart';
import 'package:flutter/services.dart';

import '../data/pdf_scanner_service.dart';
import '../domain/pdf_file_item.dart';

export '../data/pdf_scanner_service.dart' show StoragePermissionStatus;

enum PdfFilter { all, recent, downloads, large, folders }

enum PdfSortField { name, date, size }

enum PdfSortDirection { ascending, descending }

class PdfLibraryState {
  const PdfLibraryState({
    this.loading = false,
    this.items = const [],
    this.query = '',
    this.filter = PdfFilter.all,
    this.sortField = PdfSortField.date,
    this.sortDirection = PdfSortDirection.descending,
    this.favorites = const {},
    this.recents = const {},
    this.permissionStatus = StoragePermissionStatus.granted,
  });

  final bool loading;
  final List<PdfFileItem> items;
  final String query;
  final PdfFilter filter;
  final PdfSortField sortField;
  final PdfSortDirection sortDirection;
  final Set<String> favorites;
  final Map<String, DateTime> recents; // path → openedAt
  final StoragePermissionStatus permissionStatus;

  PdfLibraryState copyWith({
    bool? loading,
    List<PdfFileItem>? items,
    String? query,
    PdfFilter? filter,
    PdfSortField? sortField,
    PdfSortDirection? sortDirection,
    Set<String>? favorites,
    Map<String, DateTime>? recents,
    StoragePermissionStatus? permissionStatus,
  }) {
    return PdfLibraryState(
      loading: loading ?? this.loading,
      items: items ?? this.items,
      query: query ?? this.query,
      filter: filter ?? this.filter,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      favorites: favorites ?? this.favorites,
      recents: recents ?? this.recents,
      permissionStatus: permissionStatus ?? this.permissionStatus,
    );
  }
}

class PdfLibraryController extends StateNotifier<PdfLibraryState> {
  PdfLibraryController(
    this._scanner,
    this._favBox,
    this._recentsBox,
    this._timestampsBox,
  ) : super(const PdfLibraryState()) {
    _loadSavedState();
    // Delay initial refresh to allow the splash screen and initial UI to animate smoothly
    Future.delayed(const Duration(milliseconds: 500), refresh);
  }

  final PdfScannerService _scanner;
  final Box<String> _favBox;
  final Box<String> _recentsBox;
  final Box<int> _timestampsBox;

  void _loadSavedState() {
    // Migration: Wipe out old numeric keys in _favBox and _recentsBox
    final favKeysToDelete = _favBox.keys.where((k) => k is! String).toList();
    if (favKeysToDelete.isNotEmpty) _favBox.deleteAll(favKeysToDelete);

    final recentKeysToDelete = _recentsBox.keys.where((k) => k is! String).toList();
    if (recentKeysToDelete.isNotEmpty) _recentsBox.deleteAll(recentKeysToDelete);

    final recents = <String, DateTime>{};
    final now = DateTime.now();
    for (final path in _recentsBox.values) {
      final ms = _timestampsBox.get(path);
      recents[path] = ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : now.subtract(const Duration(days: 30));
    }
    state = state.copyWith(
      favorites: _favBox.values.toSet(),
      recents: recents,
    );
  }

  Future<void> refresh({bool requestPermission = false}) async {
    state = state.copyWith(loading: true);
    final result = await _scanner.scan(requestPermission: requestPermission);
    state = state.copyWith(
      loading: false,
      items: result.files,
      permissionStatus: result.permissionStatus,
    );
  }

  void setQuery(String query) => state = state.copyWith(query: query);
  void setFilter(PdfFilter filter) => state = state.copyWith(filter: filter);
  void setSortField(PdfSortField field) =>
      state = state.copyWith(sortField: field);
  void setSortDirection(PdfSortDirection direction) =>
      state = state.copyWith(sortDirection: direction);

  Future<void> toggleFavorite(PdfFileItem item) async {
    HapticFeedback.selectionClick();
    final favorites = {...state.favorites};
    if (favorites.contains(item.path)) {
      favorites.remove(item.path);
      await _favBox.delete(item.path);
    } else {
      favorites.add(item.path);
      await _favBox.put(item.path, item.path);
    }
    state = state.copyWith(favorites: favorites);
  }

  Future<void> markRecent(PdfFileItem item) async {
    final now = DateTime.now();
    final recents = {...state.recents, item.path: now};
    await _recentsBox.put(item.path, item.path);
    await _timestampsBox.put(item.path, now.millisecondsSinceEpoch);
    state = state.copyWith(recents: recents);
  }

  Future<bool> renameFile(PdfFileItem item, String newName) async {
    try {
      final oldFile = File(item.path);
      if (!await oldFile.exists()) return false;

      // Sanitize newName to prevent path traversal
      final sanitizedName = newName.replaceAll(RegExp(r'[/\\]|\.\.'), '').trim();
      if (sanitizedName.isEmpty) return false;

      final dir = oldFile.parent.path;
      final newPath = '$dir${Platform.pathSeparator}$sanitizedName.pdf';
      final newFile = File(newPath);
      if (await newFile.exists()) return false;

      await oldFile.rename(newPath);

      // Update Hive boxes keys if they were favored or recent
      if (state.favorites.contains(item.path)) {
        await _favBox.delete(item.path);
        await _favBox.put(newPath, newPath);
      }
      if (state.recents.containsKey(item.path)) {
        await _recentsBox.delete(item.path);
        await _recentsBox.put(newPath, newPath);
        final ms = _timestampsBox.get(item.path);
        if (ms != null) {
          await _timestampsBox.delete(item.path);
          await _timestampsBox.put(newPath, ms);
        }
      }

      await refresh();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> clearRecents() async {
    await _recentsBox.clear();
    await _timestampsBox.clear();
    state = state.copyWith(recents: const {});
  }

  List<PdfFileItem> filteredItems(
      {bool favoritesOnly = false, bool recentsOnly = false}) {
    final q = state.query.trim().toLowerCase();
    final now = DateTime.now();
    var filtered = state.items.where((e) {
      if (favoritesOnly && !state.favorites.contains(e.path)) return false;
      if (recentsOnly && !state.recents.containsKey(e.path)) return false;
      if (state.filter == PdfFilter.downloads &&
          !e.path.toLowerCase().contains('download')) {
        return false;
      }
      if (state.filter == PdfFilter.recent &&
          now.difference(e.lastModified).inDays > 7) {
        return false;
      }
      if (state.filter == PdfFilter.large && e.sizeBytes < 10 * 1024 * 1024) {
        return false;
      }
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    if (state.sortField == PdfSortField.name) {
      final nameCache = <String, String>{};
      String getLowerName(String name) => nameCache.putIfAbsent(name, () => name.toLowerCase());

      filtered.sort((a, b) {
        final nameA = getLowerName(a.name);
        final nameB = getLowerName(b.name);
        final cmp = nameA.compareTo(nameB);
        return state.sortDirection == PdfSortDirection.ascending ? cmp : -cmp;
      });
    } else {
      filtered.sort((a, b) {
        int cmp = 0;
        switch (state.sortField) {
          case PdfSortField.name:
            break; // Handled above
          case PdfSortField.date:
            cmp = a.lastModified.compareTo(b.lastModified);
            break;
          case PdfSortField.size:
            cmp = a.sizeBytes.compareTo(b.sizeBytes);
            break;
        }
        return state.sortDirection == PdfSortDirection.ascending ? cmp : -cmp;
      });
    }

    return filtered;
  }

  Map<String, List<PdfFileItem>> groupedByFolder() {
    final filtered = filteredItems();
    final groups = <String, List<PdfFileItem>>{};
    for (final item in filtered) {
      final folder = item.locationLabel;
      groups.putIfAbsent(folder, () => []).add(item);
    }
    return groups;
  }

  /// Returns recents enriched with openedAt, grouped: Today / Yesterday / This Week / Older
  Map<String, List<PdfFileItem>> groupedRecents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final groups = <String, List<PdfFileItem>>{
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Older': [],
    };

    final fallbackDate = DateTime(0);

    for (final e in state.items) {
      final openedAt = state.recents[e.path];
      if (openedAt == null) continue;

      final item = e.copyWith(openedAt: openedAt);

      if (openedAt.year == today.year && openedAt.month == today.month && openedAt.day == today.day) {
        groups['Today']!.add(item);
      } else if (openedAt.year == yesterday.year && openedAt.month == yesterday.month && openedAt.day == yesterday.day) {
        groups['Yesterday']!.add(item);
      } else if (openedAt.isAfter(weekAgo) || (openedAt.year == weekAgo.year && openedAt.month == weekAgo.month && openedAt.day == weekAgo.day)) {
        groups['This Week']!.add(item);
      } else {
        groups['Older']!.add(item);
      }
    }

    groups.removeWhere((_, list) {
      if (list.isEmpty) return true;
      list.sort((a, b) => (b.openedAt ?? fallbackDate).compareTo(a.openedAt ?? fallbackDate));
      return false;
    });

    return groups;
  }
}

final pdfLibraryControllerProvider =
    StateNotifierProvider<PdfLibraryController, PdfLibraryState>(
  (ref) => PdfLibraryController(
    const PdfScannerService(),
    Hive.box<String>(LocalBoxes.favorites),
    Hive.box<String>(LocalBoxes.recents),
    Hive.box<int>(LocalBoxes.recentsTimestamps),
  ),
);