import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/logger.dart';
import 'package:hive/hive.dart';

import 'dart:io';

import '../../../data/local_boxes.dart';

import '../data/pdf_scanner_service.dart';
import '../domain/pdf_file_item.dart';
import '../../../core/utils/fuzzy_search.dart';

export '../data/pdf_scanner_service.dart' show StoragePermissionStatus;

enum PdfFilter { all, recent, downloads, large, folders }

enum PdfSortField { name, date, size }

enum PdfSortDirection { ascending, descending }

const _unchangedTag = Object();

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
    this.tags = const {},
    this.selectedTag,
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
  final Map<String, List<String>> tags; // path → list of tags
  final String? selectedTag;

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
    Map<String, List<String>>? tags,
    Object? selectedTag = _unchangedTag,
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
      tags: tags ?? this.tags,
      selectedTag: identical(selectedTag, _unchangedTag)
          ? this.selectedTag
          : selectedTag as String?,
    );
  }
}

class PdfLibraryController extends StateNotifier<PdfLibraryState> {
  PdfLibraryController(
    this._scanner,
    this._favBox,
    this._recentsBox,
    this._timestampsBox,
    this._tagsBox,
  ) : super(const PdfLibraryState()) {
    _loadSavedState();
    // Yield to the initial UI without adding a fixed delay before the isolate scan.
    _initialRefresh = Timer(Duration.zero, refresh);
  }

  Timer? _initialRefresh;
  int _refreshGeneration = 0;
  Future<void>? _activeRefresh;
  Future<void> _pendingMutation = Future<void>.value();

  // Serialize metadata read-modify-write operations, including scan commits.
  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _pendingMutation.then((_) => action());
    _pendingMutation =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  void dispose() {
    _initialRefresh?.cancel();
    _refreshGeneration++;
    super.dispose();
  }

  final PdfScannerService _scanner;
  final Box<String> _favBox;
  final Box<String> _recentsBox;
  final Box<int> _timestampsBox;
  final Box<List<String>> _tagsBox;

  void _loadSavedState() {
    // Migration: Wipe out old numeric keys in _favBox and _recentsBox
    final favKeysToDelete = _favBox.keys.where((k) => k is! String).toList();
    if (favKeysToDelete.isNotEmpty) _favBox.deleteAll(favKeysToDelete);

    final recentKeysToDelete =
        _recentsBox.keys.where((k) => k is! String).toList();
    if (recentKeysToDelete.isNotEmpty) {
      _recentsBox.deleteAll(recentKeysToDelete);
    }

    final recents = <String, DateTime>{};
    final now = DateTime.now();
    final timestamps = _timestampsBox.toMap();
    for (final path in _recentsBox.values) {
      final ms = timestamps[path];
      recents[path] = ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : now.subtract(const Duration(days: 30));
    }
    final tags = <String, List<String>>{};
    for (final key in _tagsBox.keys) {
      if (key is String) {
        tags[key] = _tagsBox.get(key) ?? [];
      }
    }

    state = state.copyWith(
      favorites: _favBox.values.toSet(),
      recents: recents,
      tags: tags,
    );
  }

  Future<void> refresh({bool requestPermission = false}) {
    _initialRefresh?.cancel();
    if (!mounted) return Future<void>.value();
    // Share only live work, never a completed/cached library. An explicit
    // permission request must still run even while a passive scan is pending.
    if (!requestPermission && _activeRefresh != null) return _activeRefresh!;
    final generation = ++_refreshGeneration;
    final refresh = _refresh(generation, requestPermission: requestPermission);
    _activeRefresh = refresh;
    unawaited(refresh.then((_) {
      if (identical(_activeRefresh, refresh)) _activeRefresh = null;
    }));
    return refresh;
  }

  Future<void> _refresh(int generation,
      {required bool requestPermission}) async {
    // A partial index is useful for an empty library, but must not shrink an
    // existing list on routine refresh. Keep loading until the fresh full result;
    // do not merge/re-expose unchecked old paths as if they had been revalidated.
    final allowIndexed = state.items.isEmpty;
    var scanCompleted = false;
    state = state.copyWith(loading: true);
    try {
      final result = await _scanner.scan(
        requestPermission: requestPermission,
        onIndexed: (indexed) => _mutate(() async {
          if (!mounted ||
              generation != _refreshGeneration ||
              scanCompleted ||
              !allowIndexed ||
              indexed.files.isEmpty) {
            return;
          }
          // An empty index cannot establish an empty library; only the full
          // result may end loading without files. Never merge unchecked rows.
          state = state.copyWith(
            loading: false,
            items: indexed.files,
            permissionStatus: indexed.permissionStatus,
          );
        }),
      );
      scanCompleted = true;
      if (generation == _refreshGeneration) _activeRefresh = null;
      await _mutate(() async {
        if (!mounted || generation != _refreshGeneration) return;
        // The validated library is usable before optional auto-tag persistence.
        // A slow or failed metadata write must not hold the PDF list hostage.
        state = state.copyWith(
          loading: false,
          items: result.files,
          permissionStatus: result.permissionStatus,
        );
        final currentTags = Map<String, List<String>>.from(state.tags);
        const heuristics = {
          'invoice': 'Invoice',
          'receipt': 'Receipt',
          'tax': 'Tax',
          'book': 'Book',
          'ticket': 'Ticket',
          'resume': 'Resume',
          'cv': 'Resume',
          'statement': 'Statement',
        };
        for (final file in result.files) {
          final fileTags = List<String>.from(currentTags[file.path] ?? []);
          final lowerName = file.name.toLowerCase();
          for (final entry in heuristics.entries) {
            if (lowerName.contains(entry.key) &&
                !fileTags.contains(entry.value)) {
              fileTags.add(entry.value);
            }
          }
          if (fileTags.length != (currentTags[file.path]?.length ?? 0)) {
            await _tagsBox.put(file.path, fileTags);
            currentTags[file.path] = fileTags;
          }
        }
        // Metadata writes above are serialized with user edits. Publish them
        // even if a newer scan started while a Hive write was in flight.
        if (!mounted) return;
        state = state.copyWith(tags: currentTags);
      });
    } catch (_) {
      // Keep the last usable library on transient filesystem/plugin failures.
      AppLogger.warning('PDF library refresh failed');
    } finally {
      scanCompleted = true;
      if (mounted && generation == _refreshGeneration) {
        _activeRefresh = null;
        state = state.copyWith(loading: false);
      }
    }
  }

  void setQuery(String query) => state = state.copyWith(query: query);
  void setFilter(PdfFilter filter) => state = state.copyWith(filter: filter);
  void setSortField(PdfSortField field) =>
      state = state.copyWith(sortField: field);
  void setSortDirection(PdfSortDirection direction) =>
      state = state.copyWith(sortDirection: direction);
  void setSelectedTag(String? tag) => state = state.copyWith(selectedTag: tag);

  Future<void> addTag(PdfFileItem item, String tag) => _mutate(() async {
        if (!mounted) return;
        tag = tag.trim();
        if (tag.isEmpty) return;
        final tags = Map<String, List<String>>.from(state.tags);
        final fileTags = List<String>.from(tags[item.path] ?? []);
        if (!fileTags.contains(tag)) {
          fileTags.add(tag);
          tags[item.path] = fileTags;
          await _tagsBox.put(item.path, fileTags);
          if (mounted) state = state.copyWith(tags: tags);
        }
      });

  Future<void> removeTag(PdfFileItem item, String tag) => _mutate(() async {
        if (!mounted) return;
        final tags = Map<String, List<String>>.from(state.tags);
        final fileTags = List<String>.from(tags[item.path] ?? []);
        if (fileTags.contains(tag)) {
          fileTags.remove(tag);
          if (fileTags.isEmpty) {
            tags.remove(item.path);
            await _tagsBox.delete(item.path);
          } else {
            tags[item.path] = fileTags;
            await _tagsBox.put(item.path, fileTags);
          }
          if (mounted) state = state.copyWith(tags: tags);
        }
      });

  List<String> getAllTags() {
    final allTags = <String>{};
    for (final fileTags in state.tags.values) {
      allTags.addAll(fileTags);
    }
    return allTags.toList()..sort();
  }

  Future<void> toggleFavorite(PdfFileItem item) => _mutate(() async {
        if (!mounted) return;

        final favorites = {...state.favorites};
        if (favorites.contains(item.path)) {
          favorites.remove(item.path);
          await _favBox.delete(item.path);
        } else {
          favorites.add(item.path);
          await _favBox.put(item.path, item.path);
        }
        if (mounted) state = state.copyWith(favorites: favorites);
      });

  Future<void> markRecent(PdfFileItem item) => _mutate(() async {
        if (!mounted) return;
        final now = DateTime.now();
        final recents = {...state.recents, item.path: now};
        await _recentsBox.put(item.path, item.path);
        await _timestampsBox.put(item.path, now.millisecondsSinceEpoch);
        if (mounted) {
          state = state.copyWith(
            recents: recents,
            items: state.items.any((file) => file.path == item.path)
                ? state.items
                : [...state.items, item],
          );
        }
      });

  Future<bool> renameFile(PdfFileItem item, String newName) =>
      _mutate(() async {
        if (!mounted) return false;
        var name = newName.trim();
        // Reject invalid names rather than silently turning traversal into a name.
        if (name.isEmpty ||
            name == '.' ||
            name == '..' ||
            RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
            name.endsWith('.')) {
          return false;
        }
        if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
        if (RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])\.',
                caseSensitive: false)
            .hasMatch(name)) {
          return false;
        }
        final newPath = p.join(p.dirname(item.path), name);
        final previous = state;
        try {
          if (await FileSystemEntity.type(item.path, followLinks: false) !=
              FileSystemEntityType.file) {
            return false;
          }
          if (p.equals(newPath, item.path)) return true;
          if (await FileSystemEntity.type(newPath, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return false;
          }
          await File(item.path).rename(newPath);
          _invalidateScans();
          final replacement = PdfFileItem(
            path: newPath,
            name: name,
            sizeBytes: item.sizeBytes,
            lastModified: item.lastModified,
            locationLabel: item.locationLabel,
            isEncrypted: item.isEncrypted,
            isCorrupted: item.isCorrupted,
            pageCount: item.pageCount,
            openedAt: item.openedAt,
          );
          final favorites = {...previous.favorites};
          final recents = {...previous.recents};
          final tags = Map<String, List<String>>.from(previous.tags);
          if (favorites.remove(item.path)) favorites.add(newPath);
          final openedAt = recents.remove(item.path);
          if (openedAt != null) recents[newPath] = openedAt;
          final fileTags = tags.remove(item.path);
          if (fileTags != null) tags[newPath] = fileTags;
          if (mounted) {
            state = state.copyWith(
              items: [
                for (final file in state.items)
                  if (file.path == item.path) replacement else file
              ],
              favorites: favorites,
              recents: recents,
              tags: tags,
            );
          }
          // The filesystem operation succeeded: a metadata failure must not report
          // that the old file still exists or invite a duplicate rename.
          try {
            if (favorites.contains(newPath)) {
              await _favBox.put(newPath, newPath);
            }
            if (openedAt != null) await _recentsBox.put(newPath, newPath);
            final timestamp = _timestampsBox.get(item.path);
            if (timestamp != null) await _timestampsBox.put(newPath, timestamp);
            if (fileTags != null) await _tagsBox.put(newPath, fileTags);
            await _removeMetadata(item.path);
          } catch (_) {
            AppLogger.warning(
                'PDF renamed, but saved metadata could not be migrated');
          }
          return true;
        } on FileSystemException {
          return false;
        }
      });

  void _invalidateScans() {
    _initialRefresh?.cancel();
    _refreshGeneration++;
    _activeRefresh = null;
    if (mounted) state = state.copyWith(loading: false);
  }

  Future<void> _removeMetadata(String path) async {
    await _favBox.delete(path);
    await _recentsBox.delete(path);
    await _timestampsBox.delete(path);
    await _tagsBox.delete(path);
  }

  Future<bool> deleteFile(PdfFileItem item) =>
      _removeFile(item, deleteFromDisk: true);

  Future<bool> removeMissingFile(PdfFileItem item) =>
      _removeFile(item, deleteFromDisk: false);

  Future<bool> _removeFile(PdfFileItem item, {required bool deleteFromDisk}) =>
      _mutate(() async {
        if (!mounted) return false;
        try {
          final type =
              await FileSystemEntity.type(item.path, followLinks: false);
          if (type != FileSystemEntityType.file &&
              type != FileSystemEntityType.notFound) {
            return false;
          }
          if (!deleteFromDisk && type != FileSystemEntityType.notFound) {
            return false;
          }
          if (type == FileSystemEntityType.file) await File(item.path).delete();
        } on FileSystemException {
          return false;
        }
        _invalidateScans();
        if (mounted) {
          state = state.copyWith(
            items: state.items.where((file) => file.path != item.path).toList(),
            favorites: {...state.favorites}..remove(item.path),
            recents: {...state.recents}..remove(item.path),
            tags: {...state.tags}..remove(item.path),
          );
        }
        try {
          await _removeMetadata(item.path);
        } catch (_) {
          AppLogger.warning(
              'PDF deleted, but saved metadata could not be removed');
        }
        return true;
      });

  Future<void> clearRecents() => _mutate(() async {
        if (!mounted) return;
        await _recentsBox.clear();
        await _timestampsBox.clear();
        if (mounted) state = state.copyWith(recents: const {});
      });

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
      if (q.isNotEmpty && !isFuzzyMatch(e.name.toLowerCase(), q)) {
        return false;
      }
      if (state.selectedTag != null && state.selectedTag!.isNotEmpty) {
        final itemTags = state.tags[e.path] ?? [];
        if (!itemTags.contains(state.selectedTag)) {
          return false;
        }
      }
      return true;
    }).toList();

    if (state.sortField == PdfSortField.name) {
      final nameCache = <String, String>{};
      String getLowerName(String name) =>
          nameCache.putIfAbsent(name, () => name.toLowerCase());

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

      if (openedAt.year == today.year &&
          openedAt.month == today.month &&
          openedAt.day == today.day) {
        groups['Today']!.add(item);
      } else if (openedAt.year == yesterday.year &&
          openedAt.month == yesterday.month &&
          openedAt.day == yesterday.day) {
        groups['Yesterday']!.add(item);
      } else if (openedAt.isAfter(weekAgo) ||
          (openedAt.year == weekAgo.year &&
              openedAt.month == weekAgo.month &&
              openedAt.day == weekAgo.day)) {
        groups['This Week']!.add(item);
      } else {
        groups['Older']!.add(item);
      }
    }

    groups.removeWhere((_, list) {
      if (list.isEmpty) return true;
      list.sort((a, b) =>
          (b.openedAt ?? fallbackDate).compareTo(a.openedAt ?? fallbackDate));
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
    Hive.box<List<String>>(LocalBoxes.tags),
  ),
);
