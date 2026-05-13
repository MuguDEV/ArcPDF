import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../data/local_boxes.dart';
import '../data/pdf_scanner_service.dart';
import '../domain/pdf_file_item.dart';

export '../data/pdf_scanner_service.dart' show StoragePermissionStatus;

enum PdfFilter { all, recent, downloads, large }

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
    refresh();
  }

  final PdfScannerService _scanner;
  final Box<String> _favBox;
  final Box<String> _recentsBox;
  final Box<int> _timestampsBox;

  void _loadSavedState() {
    final recents = <String, DateTime>{};
    for (final key in _recentsBox.keys) {
      final path = _recentsBox.get(key);
      if (path == null) continue;
      final ms = _timestampsBox.get(path);
      recents[path] = ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : DateTime.now().subtract(const Duration(days: 30));
    }
    state = state.copyWith(
      favorites: _favBox.values.toSet(),
      recents: recents,
    );
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    final result = await _scanner.scan();
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
    final favorites = {...state.favorites};
    if (favorites.contains(item.path)) {
      favorites.remove(item.path);
      dynamic keyToDelete;
      for (final key in _favBox.keys) {
        if (_favBox.get(key) == item.path) {
          keyToDelete = key;
          break;
        }
      }
      if (keyToDelete != null) await _favBox.delete(keyToDelete);
    } else {
      favorites.add(item.path);
      await _favBox.add(item.path);
    }
    state = state.copyWith(favorites: favorites);
  }

  Future<void> markRecent(PdfFileItem item) async {
    final now = DateTime.now();
    final recents = {...state.recents, item.path: now};
    // Upsert path in recents box
    bool found = false;
    for (final key in _recentsBox.keys) {
      if (_recentsBox.get(key) == item.path) {
        found = true;
        break;
      }
    }
    if (!found) await _recentsBox.add(item.path);
    await _timestampsBox.put(item.path, now.millisecondsSinceEpoch);
    state = state.copyWith(recents: recents);
  }

  List<PdfFileItem> filteredItems(
      {bool favoritesOnly = false, bool recentsOnly = false}) {
    final q = state.query.trim().toLowerCase();
    var filtered = state.items.where((e) {
      if (favoritesOnly && !state.favorites.contains(e.path)) return false;
      if (recentsOnly && !state.recents.containsKey(e.path)) return false;
      if (state.filter == PdfFilter.downloads &&
          !e.path.toLowerCase().contains('download')) {
        return false;
      }
      if (state.filter == PdfFilter.recent &&
          DateTime.now().difference(e.lastModified).inDays > 7) {
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

    filtered.sort((a, b) {
      int cmp = 0;
      switch (state.sortField) {
        case PdfSortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case PdfSortField.date:
          cmp = a.lastModified.compareTo(b.lastModified);
          break;
        case PdfSortField.size:
          cmp = a.sizeBytes.compareTo(b.sizeBytes);
          break;
      }
      return state.sortDirection == PdfSortDirection.ascending ? cmp : -cmp;
    });

    return filtered;
  }

  /// Returns recents enriched with openedAt, grouped: Today / Yesterday / This Week / Older
  Map<String, List<PdfFileItem>> groupedRecents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final enriched = state.items
        .where((e) => state.recents.containsKey(e.path))
        .map((e) => e.copyWith(openedAt: state.recents[e.path]))
        .toList()
      ..sort((a, b) =>
          (b.openedAt ?? DateTime(0)).compareTo(a.openedAt ?? DateTime(0)));

    final groups = <String, List<PdfFileItem>>{
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Older': [],
    };

    for (final item in enriched) {
      final d = DateTime(
          item.openedAt!.year, item.openedAt!.month, item.openedAt!.day);
      if (!d.isBefore(today)) {
        groups['Today']!.add(item);
      } else if (!d.isBefore(yesterday)) {
        groups['Yesterday']!.add(item);
      } else if (!d.isBefore(weekAgo)) {
        groups['This Week']!.add(item);
      } else {
        groups['Older']!.add(item);
      }
    }
    groups.removeWhere((_, v) => v.isEmpty);
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
