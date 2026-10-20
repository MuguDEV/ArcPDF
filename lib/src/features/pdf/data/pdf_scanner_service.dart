import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'pdf_media_store_index.dart';

import 'package:external_path/external_path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/utils/logger.dart';
import '../domain/pdf_file_item.dart';

enum StoragePermissionStatus {
  granted,
  denied,
  permanentlyDenied,
}

class ScanResult {
  const ScanResult({required this.files, required this.permissionStatus});
  final List<PdfFileItem> files;
  final StoragePermissionStatus permissionStatus;
}

class PdfScannerService {
  const PdfScannerService();

  Future<StoragePermissionStatus> requestPermission(
      {bool request = true}) async {
    if (!Platform.isAndroid) return StoragePermissionStatus.granted;

    // Try MANAGE_EXTERNAL_STORAGE first (full access, works Android 6+)
    var manageStatus = await Permission.manageExternalStorage.status;
    if (manageStatus.isGranted) return StoragePermissionStatus.granted;

    if (request) {
      manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return StoragePermissionStatus.granted;
    }

    // Fallback: legacy READ_EXTERNAL_STORAGE (Android ≤ 12)
    var storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return StoragePermissionStatus.granted;

    if (request) {
      storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return StoragePermissionStatus.granted;
    }

    if (manageStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
      return StoragePermissionStatus.permanentlyDenied;
    }
    return StoragePermissionStatus.denied;
  }

  @visibleForTesting
  Future<List<String>> discoveryRoots() async {
    final roots = <String>{};
    if (Platform.isAndroid) {
      try {
        final ext = await ExternalPath.getExternalStorageDirectories();
        if (ext != null) {
          roots.addAll(ext.where((e) => e.isNotEmpty).cast<String>());
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to read external storage directories: $e');
        }
      }
    }
    if (Platform.isAndroid) {
      // App-specific external directories contain private working copies, not
      // library documents, and are already below the shared storage roots.
      roots.add('/storage/emulated/0');
    } else {
      roots.add((await getApplicationDocumentsDirectory()).path);
      // External storage APIs are Android-only and throw on iOS/desktop.
      if (!Platform.isIOS) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) roots.add(downloads.path);
      }
    }
    return roots.toList();
  }

  @visibleForTesting
  Future<List<String>?> indexedPaths() async =>
      Platform.isAndroid ? const PdfMediaStoreIndex().paths() : null;

  @visibleForTesting
  Future<List<String>> excludedRoots() async {
    final documents = (await getApplicationDocumentsDirectory()).path;
    return [
      p.join(documents, 'vault'),
      if (Platform.isAndroid) documents,
      (await getTemporaryDirectory()).path,
      (await getApplicationSupportDirectory()).path,
    ];
  }

  Future<ScanResult> scan({
    bool requestPermission = false,
    Future<void> Function(ScanResult)? onIndexed,
  }) async {
    // We check status without requesting on first load unless forced
    final permStatus = await this.requestPermission(request: requestPermission);
    if (permStatus != StoragePermissionStatus.granted) {
      return ScanResult(files: const [], permissionStatus: permStatus);
    }

    final excluded = await excludedRoots();
    var fullSettled = false;
    Future<ScanResult> fullScan() async {
      try {
        // Start root discovery and the walk without waiting for the index.
        return await scanDirectories(await discoveryRoots(),
            excludedRoots: excluded);
      } finally {
        // Even a failed full scan closes the optional publication window.
        fullSettled = true;
      }
    }

    final full = fullScan();
    if (onIndexed != null) {
      Future<void> publishIndexed() async {
        try {
          final paths = await indexedPaths();
          if (paths == null || fullSettled) return;
          final files = await _validatePathsInIsolate(paths, excluded);
          if (fullSettled) return;
          await onIndexed(
              ScanResult(files: files, permissionStatus: permStatus));
        } catch (_) {
          // This best-effort branch may outlive scan(). Always observe errors,
          // including validation/callback failures after the full result wins.
          AppLogger.warning('Indexed PDF discovery failed');
        }
      }

      unawaited(publishIndexed());
    }
    // Full completion is authoritative and never waits for index lookup,
    // validation, or publication. Never union potentially stale indexed rows.
    return full;
  }

  /// Scans explicitly supplied local roots without invoking platform plugins.
  Future<ScanResult> scanDirectories(
    List<String> roots, {
    List<String> excludedRoots = const [],
  }) async {
    // Heavy FS walk runs in a separate isolate — main thread stays smooth.
    final files = await Isolate.run(() => _walkRoots(roots, excludedRoots));

    return ScanResult(
      files: files,
      permissionStatus: StoragePermissionStatus.granted,
    );
  }
}

// Keep the isolate closure outside scan's shared async context: capturing a
// pending scan/callback future can make the message graph unsendable.
Future<List<PdfFileItem>> _validatePathsInIsolate(
        List<String> paths, List<String> excluded) =>
    Isolate.run(() => _validatedPaths(paths, excluded));

/// Top-level function so it is transferable to an Isolate.
List<PdfFileItem> _walkRoots(List<String> roots, List<String> excluded) {
  final out = <PdfFileItem>[];
  final seen = <String>{};
  final visitedDirectories = <String>{};
  final pending = [...roots];
  while (pending.isNotEmpty) {
    final root = pending.removeLast();
    try {
      if (_isExcluded(root, excluded)) continue;
      final dir = Directory(root);
      if (FileSystemEntity.typeSync(root, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      if (!visitedDirectories.add(dir.resolveSymbolicLinksSync())) continue;
      // List one directory at a time: an inaccessible child must not discard
      // all readable siblings (recursive listSync fails the entire root).
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is Directory) {
          pending.add(entity.path);
          continue;
        }
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.pdf')) continue;
        try {
          final item = _validatedFile(entity.path, excluded, seen);
          if (item != null) out.add(item);
        } catch (e, stack) {
          final redactedName = _redactPath(entity.path);
          AppLogger.error('Error processing file: $redactedName', e, stack);
        }
      }
    } catch (e, stack) {
      final redactedRoot = _redactPath(root);
      AppLogger.error('Error walking directory: $redactedRoot', e, stack);
    }
  }
  // Sorting large libraries is CPU work too; keep it off the UI isolate.
  out.sort((a, b) => b.lastModified.compareTo(a.lastModified));
  return out;
}

bool _isExcluded(String path, List<String> excluded) {
  final absolute = p.normalize(p.absolute(path));
  final segments = p.split(absolute).map((part) => part.toLowerCase()).toList();
  // MediaProvider renames pending/trashed files on disk. A broad-access walk
  // must not undo the index's IS_PENDING / IS_TRASHED filters.
  if (segments.any((segment) =>
      segment.startsWith('.trashed-') ||
      segment.startsWith('.pending-') ||
      segment == '.trash' ||
      segment == '.trashes')) {
    return true;
  }
  // Never descend into private app storage, including external working copies.
  for (var i = 0; i + 1 < segments.length; i++) {
    if (segments[i] == 'android' &&
        (segments[i + 1] == 'data' || segments[i + 1] == 'obb')) {
      return true;
    }
  }
  if (Platform.isAndroid &&
      (absolute == '/data' || p.isWithin('/data', absolute))) {
    return true;
  }
  return excluded.any((root) {
    final normalized = p.normalize(p.absolute(root));
    return p.equals(normalized, absolute) || p.isWithin(normalized, absolute);
  });
}

PdfFileItem? _validatedFile(
    String path, List<String> excluded, Set<String> seen) {
  if (!p.isAbsolute(path) ||
      !path.toLowerCase().endsWith('.pdf') ||
      _isExcluded(path, excluded) ||
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file) {
    return null;
  }
  final file = File(path);
  final canonical = file.resolveSymbolicLinksSync();
  // Reject aliases through symlinked ancestors as well as symlink files.
  if (!p.equals(p.normalize(p.absolute(path)), canonical) ||
      _isExcluded(canonical, excluded) ||
      !seen.add(canonical)) {
    return null;
  }
  final stat = file.statSync();
  if (stat.type != FileSystemEntityType.file || stat.size < 5) return null;
  final encrypted = _inspectPdf(file, stat.size);
  if (encrypted == null) return null;
  return PdfFileItem(
    path: p.normalize(path),
    name: p.basename(path),
    sizeBytes: stat.size,
    lastModified: stat.modified,
    locationLabel: p.basename(p.dirname(path)),
    isEncrypted: encrypted,
  );
}

List<PdfFileItem> _validatedPaths(List<String> paths, List<String> excluded) {
  final files = <PdfFileItem>[];
  final seen = <String>{};
  for (final path in paths) {
    try {
      final item = _validatedFile(path, excluded, seen);
      if (item != null) files.add(item);
    } on FileSystemException {
      // Stale/inaccessible index rows are normal; never trust index metadata.
    }
  }
  files.sort((a, b) => b.lastModified.compareTo(a.lastModified));
  return files;
}

String _redactPath(String path) {
  final parts = path.split(Platform.pathSeparator);
  if (parts.isEmpty) return 'unknown';
  final name = parts.last;
  if (name.length <= 4) return name;
  return '${name.substring(0, 2)}...${name.substring(name.length - 2)}';
}

/// Returns null for an unreadable/non-PDF file, otherwise its encryption flag.
/// Share one handle and header read instead of opening each PDF twice.
bool? _inspectPdf(File file, int size) {
  try {
    final raf = file.openSync();
    try {
      final header = String.fromCharCodes(raf.readSync(4096));
      if (!header.startsWith('%PDF-')) return null;
      if (header.contains('/Encrypt')) return true;
      if (size > 4096) {
        raf.setPositionSync(size - 4096);
        if (String.fromCharCodes(raf.readSync(4096)).contains('/Encrypt')) {
          return true;
        }
      }
      return false;
    } finally {
      raf.closeSync();
    }
  } catch (e, stack) {
    final redactedName = _redactPath(file.path);
    AppLogger.error('Error inspecting PDF: $redactedName', e, stack);
    return null;
  }
}
