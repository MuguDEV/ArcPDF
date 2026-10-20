import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';
import '../../data/local_boxes.dart';

/// Hard limits applied to every backup, both when writing and when reading, so
/// a hostile or corrupted file can never exhaust memory or CPU.
abstract final class BackupLimits {
  static const maxFileBytes = 16 * 1024 * 1024;
  static const maxEntries = 50000;

  /// Hive keys are limited to 255 bytes, so no stored path can be longer.
  static const maxPathLength = 255;
  static const maxTagsPerDocument = 64;
  static const maxTagLength = 128;
  static const maxPage = 1000000;
  static const maxZoom = 100.0;
  static const maxViewportOffset = 1000000.0;
  static const maxReadSeconds = 10 * 365 * 24 * 3600;
}

/// Why a backup operation failed. Messages are static and never contain paths.
enum BackupFailure {
  tooLarge('This backup file is too large.'),
  malformed('This file is not a valid ArcPDF backup.'),
  unsupportedVersion(
      'This backup was made by a newer version of ArcPDF. Update the app and try again.'),
  checksumMismatch('This backup is damaged and cannot be restored.'),
  invalidData('This backup contains invalid data and was not restored.'),
  unreadable('The backup file could not be read.'),
  storage('The backup could not be written.'),
  applyFailed('Restore failed. Your existing data was kept.'),
  applyFailedPartial(
      'Restore failed and some data may have been changed. Check your favorites and tags.');

  const BackupFailure(this.message);
  final String message;
}

class BackupException implements Exception {
  const BackupException(this.failure);
  final BackupFailure failure;
  String get message => failure.message;

  @override
  String toString() => 'BackupException(${failure.name})';
}

enum RestoreMode { merge, replace }

/// A reading position. Zoom and page are optional because older versions saved
/// them independently.
@immutable
class BackupViewport {
  const BackupViewport({
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

  Map<String, Object?> toJson() => {
        'page': page,
        'pageCount': pageCount,
        'x': x,
        'y': y,
        'zoom': zoom,
      };

  /// Format used by the reader's `readingViewport:<path>` session entries.
  Map<String, Object> toStoredMap() => {
        'version': 1,
        'page': page,
        'pageCount': pageCount,
        'zoom': zoom,
        'x': x,
        'y': y,
      };
}

@immutable
class BackupProgress {
  const BackupProgress({this.page, this.zoom, this.readSeconds, this.viewport});

  final int? page;
  final double? zoom;
  final int? readSeconds;
  final BackupViewport? viewport;

  bool get hasPosition => page != null || zoom != null;

  Map<String, Object?> toJson() => {
        if (page != null) 'page': page,
        if (readSeconds != null) 'readSeconds': readSeconds,
        if (viewport != null) 'viewport': viewport!.toJson(),
        if (zoom != null) 'zoom': zoom,
      };
}

/// Non-secret lock preferences. PINs, patterns, biometric state and whether a
/// lock is enabled are deliberately not part of a backup.
@immutable
class BackupSecurity {
  const BackupSecurity(
      {required this.lockType, required this.requireLockOnResume});

  /// Index into the app's `LockType` enum (0 = pin, 1 = pattern).
  final int lockType;
  final bool requireLockOnResume;

  Map<String, Object?> toJson() => {
        'lockType': lockType == 1 ? 'pattern' : 'pin',
        'requireLockOnResume': requireLockOnResume,
      };
}

@immutable
class BackupPreview {
  const BackupPreview({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.favorites,
    required this.taggedDocuments,
    required this.tags,
    required this.progress,
    required this.hasSecurityPreferences,
  });

  final int schemaVersion;
  final String appVersion;
  final DateTime createdAt;
  final int favorites;
  final int taggedDocuments;
  final int tags;
  final int progress;
  final bool hasSecurityPreferences;
}

/// A fully validated backup. Instances only exist for data that passed the
/// schema, size, type and checksum checks (or that was just read locally).
class BackupArchive {
  BackupArchive({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.favorites,
    required this.tags,
    required this.progress,
    this.security,
  });

  static const format = 'arcpdf-backup';
  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final String appVersion;
  final DateTime createdAt;
  final List<String> favorites;
  final Map<String, List<String>> tags;
  final Map<String, BackupProgress> progress;
  final BackupSecurity? security;

  BackupPreview get preview => BackupPreview(
        schemaVersion: schemaVersion,
        appVersion: appVersion,
        createdAt: createdAt,
        favorites: favorites.length,
        taggedDocuments: tags.length,
        tags: {for (final list in tags.values) ...list}.length,
        progress: progress.length,
        hasSecurityPreferences: security != null,
      );

  Map<String, Object?> _dataJson() {
    final sortedFavorites = [...favorites]..sort();
    return {
      'favorites': sortedFavorites,
      'progress': {
        for (final key in progress.keys.toList()..sort())
          key: progress[key]!.toJson(),
      },
      if (security != null) 'security': security!.toJson(),
      'tags': {
        for (final key in tags.keys.toList()..sort()) key: tags[key],
      },
    };
  }

  /// Integrity check only (detects truncation/corruption, not tampering).
  static String checksumOf(Map<String, Object?> data) =>
      'sha256:${sha256.convert(utf8.encode(jsonEncode(_canonical(data))))}';

  static Object? _canonical(Object? value) {
    if (value is Map) {
      return SplayTreeMap<String, Object?>.from({
        for (final entry in value.entries)
          entry.key as String: _canonical(entry.value),
      });
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Map<String, Object?> toJson() {
    final data = _dataJson();
    return {
      'format': format,
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'checksum': checksumOf(data),
      'data': data,
    };
  }

  Uint8List encode() {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
    if (bytes.length > BackupLimits.maxFileBytes) {
      throw const BackupException(BackupFailure.tooLarge);
    }
    return bytes;
  }

  /// Parses and validates untrusted bytes. Throws [BackupException] for any
  /// problem; never partially accepts a file.
  static BackupArchive parse(Uint8List bytes) {
    if (bytes.length > BackupLimits.maxFileBytes) {
      throw const BackupException(BackupFailure.tooLarge);
    }
    final Object? decoded;
    try {
      var start = 0;
      if (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF) {
        start = 3;
      }
      decoded = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, start),
          allowMalformed: false));
    } on FormatException {
      throw const BackupException(BackupFailure.malformed);
    }
    if (decoded is! Map || decoded['format'] != format) {
      throw const BackupException(BackupFailure.malformed);
    }
    final version = decoded['schemaVersion'];
    if (version is! int || version < 1) {
      throw const BackupException(BackupFailure.malformed);
    }
    if (version > currentSchemaVersion) {
      throw const BackupException(BackupFailure.unsupportedVersion);
    }
    final appVersion = decoded['appVersion'];
    final createdRaw = decoded['createdAt'];
    final checksum = decoded['checksum'];
    final data = decoded['data'];
    if (appVersion is! String ||
        appVersion.isEmpty ||
        appVersion.length > 64 ||
        createdRaw is! String ||
        createdRaw.length > 64 ||
        checksum is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(checksum) ||
        data is! Map) {
      throw const BackupException(BackupFailure.malformed);
    }
    final createdAt = DateTime.tryParse(createdRaw);
    if (createdAt == null) throw const BackupException(BackupFailure.malformed);

    final archive = BackupArchive(
      schemaVersion: version,
      appVersion: appVersion,
      createdAt: createdAt,
      favorites: _parseFavorites(data['favorites']),
      tags: _parseTags(data['tags']),
      progress: _parseProgress(data['progress']),
      security: _parseSecurity(data['security']),
    );
    // Verified against the normalized model, so unknown extra keys are neither
    // trusted nor applied.
    if (archive.toJson()['checksum'] != checksum) {
      throw const BackupException(BackupFailure.checksumMismatch);
    }
    return archive;
  }

  static BackupException get _invalid =>
      const BackupException(BackupFailure.invalidData);

  static bool isValidPath(Object? value) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= BackupLimits.maxPathLength &&
      utf8.encode(value).length <= BackupLimits.maxPathLength &&
      !RegExp(r'[\x00-\x1F\x7F]').hasMatch(value);

  static List<String> _parseFavorites(Object? raw) {
    if (raw is! List || raw.length > BackupLimits.maxEntries) throw _invalid;
    final result = <String>{};
    for (final item in raw) {
      if (!isValidPath(item)) throw _invalid;
      result.add(item as String);
    }
    return result.toList();
  }

  static Map<String, List<String>> _parseTags(Object? raw) {
    if (raw is! Map || raw.length > BackupLimits.maxEntries) throw _invalid;
    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      final list = entry.value;
      if (!isValidPath(entry.key) ||
          list is! List ||
          list.length > BackupLimits.maxTagsPerDocument) {
        throw _invalid;
      }
      final tags = <String>{};
      for (final tag in list) {
        if (tag is! String ||
            tag.trim().isEmpty ||
            tag.length > BackupLimits.maxTagLength ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(tag)) {
          throw _invalid;
        }
        tags.add(tag);
      }
      if (tags.isNotEmpty) result[entry.key as String] = tags.toList();
    }
    return result;
  }

  static int? _optionalInt(Object? v, int min, int max) {
    if (v == null) return null;
    if (v is! int || v < min || v > max) throw _invalid;
    return v;
  }

  static double _finite(Object? v, double min, double max,
      {bool exclusiveMin = false}) {
    if (v is! num) throw _invalid;
    final value = v.toDouble();
    if (!value.isFinite ||
        value > max ||
        (exclusiveMin ? value <= min : value < min)) {
      throw _invalid;
    }
    return value;
  }

  static Map<String, BackupProgress> _parseProgress(Object? raw) {
    if (raw is! Map || raw.length > BackupLimits.maxEntries) throw _invalid;
    final result = <String, BackupProgress>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (!isValidPath(entry.key) || value is! Map) throw _invalid;
      final page = _optionalInt(value['page'], 1, BackupLimits.maxPage);
      final zoomRaw = value['zoom'];
      final zoom = zoomRaw == null
          ? null
          : _finite(zoomRaw, 0, BackupLimits.maxZoom, exclusiveMin: true);
      final seconds =
          _optionalInt(value['readSeconds'], 0, BackupLimits.maxReadSeconds);
      BackupViewport? viewport;
      final viewportRaw = value['viewport'];
      if (viewportRaw != null) {
        if (viewportRaw is! Map || page == null || zoom == null) throw _invalid;
        final vPage = viewportRaw['page'];
        final vCount = viewportRaw['pageCount'];
        if (vPage is! int ||
            vCount is! int ||
            vPage != page ||
            vCount < vPage ||
            vCount > BackupLimits.maxPage) {
          throw _invalid;
        }
        final vZoom = _finite(viewportRaw['zoom'], 0, BackupLimits.maxZoom,
            exclusiveMin: true);
        if (vZoom != zoom) throw _invalid;
        viewport = BackupViewport(
          page: vPage,
          pageCount: vCount,
          zoom: vZoom,
          x: _finite(viewportRaw['x'], -BackupLimits.maxViewportOffset,
              BackupLimits.maxViewportOffset),
          y: _finite(viewportRaw['y'], -BackupLimits.maxViewportOffset,
              BackupLimits.maxViewportOffset),
        );
      }
      final progress = BackupProgress(
          page: page, zoom: zoom, readSeconds: seconds, viewport: viewport);
      if (!progress.hasPosition && seconds == null) throw _invalid;
      result[entry.key as String] = progress;
    }
    return result;
  }

  static BackupSecurity? _parseSecurity(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) throw _invalid;
    final type = raw['lockType'];
    final resume = raw['requireLockOnResume'];
    if ((type != 'pin' && type != 'pattern') || resume is! bool) {
      throw _invalid;
    }
    return BackupSecurity(
        lockType: type == 'pattern' ? 1 : 0, requireLockOnResume: resume);
  }
}

/// The boxes a backup reads and writes. Injectable so tests can use temporary
/// Hive boxes.
class BackupBoxes {
  const BackupBoxes({
    required this.favorites,
    required this.tags,
    required this.pages,
    required this.zoom,
    required this.readTime,
    required this.sessions,
    required this.settings,
  });

  factory BackupBoxes.fromHive() => BackupBoxes(
        favorites: Hive.box<String>(LocalBoxes.favorites),
        tags: Hive.box<List<String>>(LocalBoxes.tags),
        pages: Hive.box<int>(pagesBoxName),
        zoom: Hive.box<double>(zoomBoxName),
        readTime: Hive.box<int>(timeBoxName),
        sessions: Hive.box<dynamic>(LocalBoxes.sessions),
        settings: Hive.box<dynamic>(LocalBoxes.settings),
      );

  static const pagesBoxName = 'reading_progress_pages';
  static const zoomBoxName = 'reading_progress_zoom';
  static const timeBoxName = 'reading_progress_time';
  static const viewportPrefix = 'readingViewport:';

  final Box<String> favorites;
  final Box<List<String>> tags;
  final Box<int> pages;
  final Box<double> zoom;
  final Box<int> readTime;
  final Box<dynamic> sessions;
  final Box<dynamic> settings;
}

@immutable
class BackupExport {
  const BackupExport({
    required this.file,
    required this.fileName,
    required this.bytes,
    required this.preview,
  });

  final File file;
  final String fileName;
  final Uint8List bytes;
  final BackupPreview preview;
}

@immutable
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.mode,
    required this.favorites,
    required this.taggedDocuments,
    required this.progress,
    required this.keptLocalProgress,
    required this.skipped,
    required this.securityApplied,
  });

  final RestoreMode mode;
  final int favorites;
  final int taggedDocuments;
  final int progress;

  /// Merge only: reading positions that already existed here and were kept.
  final int keptLocalProgress;

  /// Entries ignored because they pointed into the private vault.
  final int skipped;
  final bool securityApplied;
}

abstract class _Edit {
  bool get isEmpty;
  Future<void> apply();
  Future<void> rollback();
  String get stage;
}

/// Staged changes to one box. The previous value of every touched key is
/// captured up front so the edit can be undone.
class _BoxEdit<T> implements _Edit {
  _BoxEdit(this.stage, this._box, this._puts, [Iterable<Object>? deletes])
      : _deletes = {...?deletes} {
    for (final key in {..._puts.keys, ..._deletes}) {
      if (_box.containsKey(key)) {
        _before[key] = _box.get(key) as T;
      } else {
        _absent.add(key);
      }
    }
  }

  @override
  final String stage;
  final Box<T> _box;
  final Map<dynamic, T> _puts;
  final Set<Object> _deletes;
  final Map<dynamic, T> _before = {};
  final Set<Object> _absent = {};

  @override
  bool get isEmpty => _puts.isEmpty && _deletes.isEmpty;

  @override
  Future<void> apply() async {
    if (_puts.isNotEmpty) await _box.putAll(_puts);
    if (_deletes.isNotEmpty) await _box.deleteAll(_deletes);
  }

  @override
  Future<void> rollback() async {
    // A closed box cannot have accepted writes after it was closed.
    if (!_box.isOpen) return;
    if (_before.isNotEmpty) await _box.putAll(_before);
    if (_absent.isNotEmpty) await _box.deleteAll(_absent);
  }
}

/// Creates and restores backups of favorites, tags, reading progress and
/// non-secret lock preferences.
///
/// Never touched: lock secrets (flutter_secure_storage), whether a lock or
/// biometric unlock is enabled, vault contents and keys, thumbnails, open tabs,
/// recents and annotations.
class BackupService {
  BackupService({
    required this.boxes,
    this.vaultDirectory,
    Future<Directory> Function()? temporaryDirectory,
    Future<String> Function()? appVersion,
    DateTime Function()? clock,
    @visibleForTesting this.debugBeforeApply,
  })  : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _appVersion = appVersion ?? _platformVersion,
        _clock = clock ?? DateTime.now;

  /// Production service using the app's opened Hive boxes.
  static Future<BackupService> create() async {
    String? vault;
    try {
      vault = p.join((await getApplicationDocumentsDirectory()).path, 'vault');
    } catch (_) {
      vault = null;
    }
    return BackupService(boxes: BackupBoxes.fromHive(), vaultDirectory: vault);
  }

  static Future<String> _platformVersion() async {
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      return version.isEmpty ? 'unknown' : version;
    } catch (_) {
      return 'unknown';
    }
  }

  static const exportPrefix = 'arcpdf-backup-';

  final BackupBoxes boxes;

  /// Paths inside this directory are never exported or restored.
  final String? vaultDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;

  /// Test hook invoked with the stage name right before each box is written.
  final Future<void> Function(String stage)? debugBeforeApply;

  Future<void> _tail = Future.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  bool _isExcluded(String path) =>
      vaultDirectory != null && p.isWithin(vaultDirectory!, path);

  // ── Export ────────────────────────────────────────────────────────────────

  Map<String, T> _entries<T>(Box<T> box) {
    final result = <String, T>{};
    for (final key in box.keys.toList()) {
      if (key is! String) continue;
      try {
        final value = box.get(key);
        if (value != null) result[key] = value;
      } catch (_) {
        // A damaged record is simply not backed up.
      }
    }
    return result;
  }

  bool _exportable(String path) =>
      BackupArchive.isValidPath(path) && !_isExcluded(path);

  /// Builds an archive from the current box contents. Invalid or out-of-range
  /// local values are omitted rather than exported.
  Future<BackupArchive> snapshot() async {
    final version = await _appVersion();
    final favorites = _entries(boxes.favorites).keys.where(_exportable).toList()
      ..sort();

    final tags = <String, List<String>>{};
    for (final entry in _entries<Object>(boxes.tags as Box<Object>).entries) {
      final value = entry.value;
      if (!_exportable(entry.key) || value is! List) continue;
      final clean = <String>{
        for (final tag in value)
          if (tag is String &&
              tag.trim().isNotEmpty &&
              tag.length <= BackupLimits.maxTagLength &&
              !RegExp(r'[\x00-\x1F\x7F]').hasMatch(tag))
            tag,
      }.take(BackupLimits.maxTagsPerDocument).toList();
      if (clean.isNotEmpty) tags[entry.key] = clean;
    }

    final pages = _entries(boxes.pages);
    final zooms = _entries(boxes.zoom);
    final times = _entries(boxes.readTime);
    final viewports = <String, Object?>{};
    for (final key in boxes.sessions.keys.toList()) {
      if (key is String && key.startsWith(BackupBoxes.viewportPrefix)) {
        viewports[key.substring(BackupBoxes.viewportPrefix.length)] =
            boxes.sessions.get(key);
      }
    }
    final paths = {
      ...pages.keys,
      ...zooms.keys,
      ...times.keys,
      ...viewports.keys
    }.where(_exportable).toList()
      ..sort();
    final progress = <String, BackupProgress>{};
    for (final path in paths) {
      final page = pages[path];
      final zoom = zooms[path];
      final seconds = times[path];
      final validPage =
          page != null && page >= 1 && page <= BackupLimits.maxPage
              ? page
              : null;
      final validZoom = zoom != null &&
              zoom.isFinite &&
              zoom > 0 &&
              zoom <= BackupLimits.maxZoom
          ? zoom
          : null;
      final validSeconds = seconds != null &&
              seconds >= 0 &&
              seconds <= BackupLimits.maxReadSeconds
          ? seconds
          : null;
      final viewport = validPage == null || validZoom == null
          ? null
          : _viewportFrom(viewports[path], validPage, validZoom);
      final entry = BackupProgress(
          page: validPage,
          zoom: validZoom,
          readSeconds: validSeconds,
          viewport: viewport);
      if (entry.hasPosition || validSeconds != null) progress[path] = entry;
    }

    final lockType = boxes.settings.get('lockType');
    final resume = boxes.settings.get('requireLockOnResume');
    return BackupArchive(
      schemaVersion: BackupArchive.currentSchemaVersion,
      appVersion: version,
      createdAt: _clock().toUtc(),
      favorites: favorites,
      tags: tags,
      progress: progress,
      security: BackupSecurity(
        lockType: lockType == 1 ? 1 : 0,
        requireLockOnResume: resume is bool ? resume : true,
      ),
    );
  }

  BackupViewport? _viewportFrom(Object? raw, int page, double zoom) {
    if (raw is! Map || raw['version'] != 1) return null;
    final count = raw['pageCount'];
    final x = raw['x'];
    final y = raw['y'];
    final vPage = raw['page'];
    final vZoom = raw['zoom'];
    const limit = BackupLimits.maxViewportOffset;
    if (vPage != page ||
        count is! int ||
        count < page ||
        count > BackupLimits.maxPage ||
        vZoom is! num ||
        vZoom.toDouble() != zoom ||
        x is! num ||
        y is! num ||
        !x.isFinite ||
        !y.isFinite ||
        x.abs() > limit ||
        y.abs() > limit) {
      return null;
    }
    return BackupViewport(
        page: page,
        pageCount: count,
        zoom: zoom,
        x: x.toDouble(),
        y: y.toDouble());
  }

  String _fileName() {
    final t = _clock().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '$exportPrefix${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
  }

  /// Writes a fresh backup to the temporary directory (replacing older export
  /// files) and returns it for sharing.
  Future<BackupExport> createExport() => _serialize(() async {
        try {
          final archive = await snapshot();
          final bytes = archive.encode();
          final directory = await _temporaryDirectory();
          await directory.create(recursive: true);
          await _pruneOldExports(directory);
          final name = _fileName();
          final target = File(p.join(directory.path, name));
          final staging = File('${target.path}.tmp');
          await staging.writeAsBytes(bytes, flush: true);
          await staging.rename(target.path);
          final preview = archive.preview;
          await AppLogger.event('backup.exported', fields: {
            'schemaVersion': archive.schemaVersion,
            'favorites': preview.favorites,
            'tagged': preview.taggedDocuments,
            'progress': preview.progress,
            'bytes': bytes.length,
          });
          return BackupExport(
              file: target, fileName: name, bytes: bytes, preview: preview);
        } on BackupException catch (error) {
          await AppLogger.event('backup.export.failed',
              fields: {'reason': error.failure.name});
          rethrow;
        } on Object catch (error, stack) {
          await AppLogger.error('backup.export.failed', error, stack);
          throw const BackupException(BackupFailure.storage);
        }
      });

  Future<void> _pruneOldExports(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is File &&
            name.startsWith(exportPrefix) &&
            (name.endsWith('.json') || name.endsWith('.json.tmp'))) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Best effort only.
    }
  }

  // ── Import ────────────────────────────────────────────────────────────────

  /// Reads and validates a backup from [path] without ever loading more than
  /// [BackupLimits.maxFileBytes].
  Future<BackupArchive> readFile(String path) async {
    final Uint8List bytes;
    try {
      if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
        throw const BackupException(BackupFailure.unreadable);
      }
      final file = File(path);
      if (await file.length() > BackupLimits.maxFileBytes) {
        throw const BackupException(BackupFailure.tooLarge);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        builder.add(chunk);
        if (builder.length > BackupLimits.maxFileBytes) {
          throw const BackupException(BackupFailure.tooLarge);
        }
      }
      bytes = builder.takeBytes();
    } on BackupException catch (error) {
      await AppLogger.event('backup.read.failed',
          fields: {'reason': error.failure.name});
      rethrow;
    } on Object {
      await AppLogger.event('backup.read.failed',
          fields: {'reason': BackupFailure.unreadable.name});
      throw const BackupException(BackupFailure.unreadable);
    }
    return parseBytes(bytes);
  }

  /// Validates raw bytes (e.g. from a picker that returned memory).
  Future<BackupArchive> parseBytes(Uint8List bytes) async {
    try {
      final archive = BackupArchive.parse(bytes);
      final preview = archive.preview;
      await AppLogger.event('backup.read', fields: {
        'schemaVersion': archive.schemaVersion,
        'favorites': preview.favorites,
        'tagged': preview.taggedDocuments,
        'progress': preview.progress,
      });
      return archive;
    } on BackupException catch (error) {
      await AppLogger.event('backup.read.failed',
          fields: {'reason': error.failure.name});
      rethrow;
    }
  }

  // ── Restore ───────────────────────────────────────────────────────────────

  /// Stages every change in memory first, then applies box by box. If any
  /// write fails, boxes already written are put back to their previous values.
  Future<BackupRestoreResult> restore(
    BackupArchive archive, {
    required RestoreMode mode,
  }) =>
      _serialize(() => _restore(archive, mode));

  Future<BackupRestoreResult> _restore(
      BackupArchive archive, RestoreMode mode) async {
    final replace = mode == RestoreMode.replace;
    final List<_Edit> edits;
    var skipped = 0;
    var keptLocal = 0;
    var progressApplied = 0;
    var favoritesCount = 0;
    var taggedCount = 0;
    var securityApplied = false;
    try {
      // ── Stage ──
      final favorites = archive.favorites.where((path) {
        final keep = !_isExcluded(path);
        if (!keep) skipped++;
        return keep;
      }).toList();
      favoritesCount = favorites.length;
      final existingFavorites = <Object, String>{};
      for (final key in boxes.favorites.keys.toList()) {
        final value = boxes.favorites.get(key);
        if (value != null) existingFavorites[key as Object] = value;
      }
      final favoritePuts = <dynamic, String>{
        for (final path in favorites)
          if (existingFavorites[path] != path) path: path,
      };
      final favoriteDeletes = replace
          ? existingFavorites.keys.where((k) => !favorites.contains(k))
          : const <Object>[];

      final tags = <String, List<String>>{};
      for (final entry in archive.tags.entries) {
        if (_isExcluded(entry.key)) {
          skipped++;
        } else {
          tags[entry.key] = entry.value;
        }
      }
      final existingTags = <Object, List<String>>{};
      for (final key in boxes.tags.keys.toList()) {
        final value = (boxes.tags as Box<Object>).get(key as Object);
        if (value is List) {
          existingTags[key] = value.whereType<String>().toList();
        }
      }
      final tagPuts = <dynamic, List<String>>{};
      for (final entry in tags.entries) {
        final current = existingTags[entry.key] ?? const <String>[];
        final next = replace
            ? entry.value
            : [
                ...current,
                ...entry.value.where((tag) => !current.contains(tag)),
              ];
        if (!listEquals(current, next)) {
          tagPuts[entry.key] = next;
        }
      }
      taggedCount = tags.length;
      final tagDeletes = replace
          ? existingTags.keys.where((k) => !tags.containsKey(k))
          : const <Object>[];

      final progress = <String, BackupProgress>{};
      for (final entry in archive.progress.entries) {
        if (_isExcluded(entry.key)) {
          skipped++;
        } else {
          progress[entry.key] = entry.value;
        }
      }
      final existingPages = _entries(boxes.pages);
      final existingZoom = _entries(boxes.zoom);
      final existingTime = _entries(boxes.readTime);
      final pagePuts = <dynamic, int>{};
      final zoomPuts = <dynamic, double>{};
      final timePuts = <dynamic, int>{};
      final viewportPuts = <dynamic, dynamic>{};
      final viewportDeletes = <Object>[];
      final targetPages = <String>{};
      final targetZoom = <String>{};
      final targetTime = <String>{};
      final targetViewports = <String>{};
      for (final entry in progress.entries) {
        final path = entry.key;
        final item = entry.value;
        var touched = false;
        final hasLocalPosition =
            existingPages.containsKey(path) || existingZoom.containsKey(path);
        if (item.hasPosition) {
          if (!replace && hasLocalPosition) {
            keptLocal++;
          } else {
            touched = true;
            final page = item.page;
            if (page != null) {
              targetPages.add(path);
              if (existingPages[path] != page) pagePuts[path] = page;
            }
            final zoom = item.zoom;
            if (zoom != null) {
              targetZoom.add(path);
              if (existingZoom[path] != zoom) zoomPuts[path] = zoom;
            }
            final key = '${BackupBoxes.viewportPrefix}$path';
            final viewport = item.viewport;
            // The viewport key adds a prefix and must still fit a Hive key.
            if (viewport != null && utf8.encode(key).length <= 255) {
              targetViewports.add(key);
              viewportPuts[key] = viewport.toStoredMap();
            } else if (!replace && boxes.sessions.containsKey(key)) {
              viewportDeletes.add(key);
            }
          }
        }
        final seconds = item.readSeconds;
        if (seconds != null) {
          if (replace) {
            targetTime.add(path);
            if (existingTime[path] != seconds) timePuts[path] = seconds;
            touched = true;
          } else if (seconds > (existingTime[path] ?? 0)) {
            timePuts[path] = seconds;
            touched = true;
          }
        }
        if (touched) progressApplied++;
      }
      if (replace) {
        viewportDeletes.addAll([
          for (final key in boxes.sessions.keys)
            if (key is String &&
                key.startsWith(BackupBoxes.viewportPrefix) &&
                !targetViewports.contains(key))
              key,
        ]);
      }

      final settingsPuts = <dynamic, dynamic>{};
      final security = archive.security;
      if (security != null) {
        final lockOn = boxes.settings.get('isLockEnabled') == true;
        final currentResume = boxes.settings.get('requireLockOnResume');
        if (!lockOn) {
          if (boxes.settings.get('lockType') != security.lockType) {
            settingsPuts['lockType'] = security.lockType;
          }
          if (currentResume != security.requireLockOnResume) {
            settingsPuts['requireLockOnResume'] = security.requireLockOnResume;
          }
        } else if (security.requireLockOnResume && currentResume == false) {
          // An active lock may only be made stricter by a backup.
          settingsPuts['requireLockOnResume'] = true;
        }
        securityApplied = settingsPuts.isNotEmpty;
      }

      edits = <_Edit>[
        _BoxEdit<String>(
            'favorites', boxes.favorites, favoritePuts, favoriteDeletes),
        _BoxEdit<List<String>>('tags', boxes.tags, tagPuts, tagDeletes),
        _BoxEdit<int>(
            'pages',
            boxes.pages,
            pagePuts,
            replace
                ? existingPages.keys.where((k) => !targetPages.contains(k))
                : null),
        _BoxEdit<double>(
            'zoom',
            boxes.zoom,
            zoomPuts,
            replace
                ? existingZoom.keys.where((k) => !targetZoom.contains(k))
                : null),
        _BoxEdit<int>(
            'time',
            boxes.readTime,
            timePuts,
            replace
                ? existingTime.keys.where((k) => !targetTime.contains(k))
                : null),
        _BoxEdit<dynamic>(
            'viewports', boxes.sessions, viewportPuts, viewportDeletes),
        _BoxEdit<dynamic>('security', boxes.settings, settingsPuts),
      ].where((edit) => !edit.isEmpty).toList();
    } on Object catch (error, stack) {
      await AppLogger.error('backup.restore.stage_failed', error, stack);
      throw const BackupException(BackupFailure.applyFailed);
    }

    // ── Apply ──
    final started = <_Edit>[];
    try {
      for (final edit in edits) {
        started.add(edit);
        await debugBeforeApply?.call(edit.stage);
        await edit.apply();
      }
    } on Object catch (error, stack) {
      var rolledBack = true;
      for (final edit in started.reversed) {
        try {
          await edit.rollback();
        } catch (_) {
          rolledBack = false;
        }
      }
      await AppLogger.error('backup.restore.failed', error, stack);
      await AppLogger.event('backup.restore.rollback',
          fields: {'complete': rolledBack, 'stages': started.length});
      throw BackupException(rolledBack
          ? BackupFailure.applyFailed
          : BackupFailure.applyFailedPartial);
    }

    final result = BackupRestoreResult(
      mode: mode,
      favorites: favoritesCount,
      taggedDocuments: taggedCount,
      progress: progressApplied,
      keptLocalProgress: keptLocal,
      skipped: skipped,
      securityApplied: securityApplied,
    );
    await AppLogger.event('backup.restored', fields: {
      'mode': mode.name,
      'favorites': result.favorites,
      'tagged': result.taggedDocuments,
      'progress': result.progress,
      'kept': result.keptLocalProgress,
      'skipped': result.skipped,
      'security': result.securityApplied,
    });
    return result;
  }
}
