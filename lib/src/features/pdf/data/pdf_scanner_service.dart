import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
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

  Future<StoragePermissionStatus> requestPermission({bool request = true}) async {
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

  Future<List<String>> _roots() async {
    final roots = <String>{};
    if (Platform.isAndroid) {
      try {
        final ext = await ExternalPath.getExternalStorageDirectories();
        if (ext != null) roots.addAll(ext.where((e) => e.isNotEmpty));
      } catch (_) {}
    }
    final appExt = await getExternalStorageDirectories();
    if (appExt != null) roots.addAll(appExt.map((e) => e.path));

    roots.addAll([
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0',
    ]);
    return roots.where((p) => Directory(p).existsSync()).toList();
  }

  Future<ScanResult> scan({bool requestPermission = false}) async {
    // We check status without requesting on first load unless forced
    final permStatus = await this.requestPermission(request: requestPermission);
    if (permStatus != StoragePermissionStatus.granted) {
      return ScanResult(files: const [], permissionStatus: permStatus);
    }

    final roots = await _roots();

    // Heavy FS walk runs in a separate isolate — main thread stays smooth
    final files = await Isolate.run(() => _walkRoots(roots));

    return ScanResult(
      files: files.sorted((a, b) => b.lastModified.compareTo(a.lastModified)),
      permissionStatus: StoragePermissionStatus.granted,
    );
  }
}

/// Top-level function so it is transferable to an Isolate.
List<PdfFileItem> _walkRoots(List<String> roots) {
  final out = <PdfFileItem>[];
  final seen = <String>{};
  for (final root in roots) {
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.pdf')) continue;
        if (seen.contains(entity.path)) continue;
        seen.add(entity.path);
        try {
          if (entity.lengthSync() == 0) continue;

          final isValid = _isValidPdf(entity);
          if (!isValid) continue;

          final isEncrypted = _isEncrypted(entity);
          out.add(PdfFileItem.fromFile(entity, isEncrypted: isEncrypted, isCorrupted: false));
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
  return out;
}

String _redactPath(String path) {
  final parts = path.split(Platform.pathSeparator);
  if (parts.isEmpty) return 'unknown';
  final name = parts.last;
  if (name.length <= 4) return name;
  return '${name.substring(0, 2)}...${name.substring(name.length - 2)}';
}

bool _isValidPdf(File file) {
  try {
    if (file.lengthSync() < 5) return false;
    final raf = file.openSync();
    final bytes = raf.readSync(5);
    raf.closeSync();
    final header = String.fromCharCodes(bytes);
    return header == '%PDF-';
  } catch (e, stack) {
    final redactedName = _redactPath(file.path);
    AppLogger.error('Error checking PDF header: $redactedName', e, stack);
    return false;
  }
}

bool _isEncrypted(File file) {
  try {
    final raf = file.openSync();
    final bytes = raf.readSync(4096);
    raf.closeSync();
    final str = String.fromCharCodes(bytes);
    if (str.contains('/Encrypt')) return true;
    
    final size = file.lengthSync();
    if (size > 4096) {
      final raf2 = file.openSync();
      raf2.setPositionSync(size - 4096);
      final endBytes = raf2.readSync(4096);
      raf2.closeSync();
      final endStr = String.fromCharCodes(endBytes);
      if (endStr.contains('/Encrypt')) return true;
    }
  } catch (e, stack) {
    final redactedName = _redactPath(file.path);
    AppLogger.error('Error checking if PDF is encrypted: $redactedName', e, stack);
  }
  return false;
}