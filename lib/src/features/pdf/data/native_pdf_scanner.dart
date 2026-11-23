import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../../../core/native/native_job_runtime.dart';
import '../domain/pdf_file_item.dart';

typedef _ScanNative = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _ScanDart = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _FreeNative = Void Function(Pointer<Utf8> value);
typedef _FreeDart = void Function(Pointer<Utf8> value);

class PdfDuplicateGroup {
  const PdfDuplicateGroup({
    required this.digest,
    required this.sizeBytes,
    required this.reclaimableBytes,
    required this.paths,
  });

  final String digest;
  final int sizeBytes;
  final int reclaimableBytes;
  final List<String> paths;

  factory PdfDuplicateGroup.fromJson(Map<String, dynamic> json) =>
      PdfDuplicateGroup(
        digest: json['digest'] as String,
        sizeBytes: json['sizeBytes'] as int,
        reclaimableBytes: json['reclaimableBytes'] as int,
        paths: List<String>.from(json['paths'] as List),
      );
}

class NativeScanStats {
  const NativeScanStats({
    required this.elapsedMillis,
    required this.filesConsidered,
    required this.filesHashed,
    required this.cacheHits,
    required this.workers,
  });

  final int elapsedMillis;
  final int filesConsidered;
  final int filesHashed;
  final int cacheHits;
  final int workers;

  factory NativeScanStats.fromJson(Map<String, dynamic> json) =>
      NativeScanStats(
        elapsedMillis: json['elapsedMillis'] as int,
        filesConsidered: json['filesConsidered'] as int,
        filesHashed: json['filesHashed'] as int,
        cacheHits: json['cacheHits'] as int,
        workers: json['workers'] as int,
      );
}

class NativePdfScanResult {
  const NativePdfScanResult({
    required this.files,
    required this.duplicateGroups,
    required this.stats,
  });

  final List<PdfFileItem> files;
  final List<PdfDuplicateGroup> duplicateGroups;
  final NativeScanStats stats;
}

class NativePdfScanner {
  const NativePdfScanner._();

  static Future<NativePdfScanResult?> scan({
    required List<String> roots,
    required List<String> excludedRoots,
    String? cachePath,
    int? maxWorkers,
    String? libraryPath,
    void Function(NativeJobHandle handle)? onHandle,
    void Function(NativeJobSnapshot event)? onEvent,
  }) async {
    final payload = {
      'roots': roots,
      'excludedRoots': excludedRoots,
      'cachePath': cachePath,
      'maxWorkers': maxWorkers,
    };
    final runtime = NativeJobRuntime.tryOpen(libraryPath: libraryPath);
    if (runtime != null) {
      try {
        final handle = runtime.submit({'kind': 'scan', 'payload': payload});
        onHandle?.call(handle);
        final result = await runtime.wait(handle, onEvent: onEvent);
        return _fromJson(result);
      } on NativeJobCancelledException {
        rethrow;
      } on NativeJobException {
        return null;
      }
    }
    final request = jsonEncode(payload);
    return Isolate.run(() => _invoke((request, libraryPath)));
  }

  static NativePdfScanResult? _invoke((String, String?) input) {
    try {
      return _invokeUnchecked(input);
    } on Object {
      // Native scanning is an acceleration path. The caller falls back to the
      // proven Dart scanner if the library is missing or a response is invalid.
      return null;
    }
  }

  static NativePdfScanResult? _invokeUnchecked((String, String?) input) {
    DynamicLibrary library;
    library = DynamicLibrary.open(input.$2 ?? _defaultLibraryName());
    final scan = library.lookupFunction<_ScanNative, _ScanDart>(
      'arcpdf_scan_json',
    );
    final free = library.lookupFunction<_FreeNative, _FreeDart>(
      'arcpdf_free_string',
    );
    final request = input.$1.toNativeUtf8();
    Pointer<Utf8> response = nullptr;
    try {
      response = scan(request);
      if (response == nullptr) return null;
      final decoded = jsonDecode(response.toDartString());
      if (decoded is! Map<String, dynamic> || decoded['error'] != null) {
        return null;
      }
      return _fromJson(decoded);
    } finally {
      calloc.free(request);
      if (response != nullptr) free(response);
    }
  }

  static NativePdfScanResult _fromJson(Map<String, dynamic> decoded) {
    final files = (decoded['files'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (item) => PdfFileItem(
            path: item['path'] as String,
            name: item['name'] as String,
            sizeBytes: item['sizeBytes'] as int,
            lastModified: DateTime.fromMillisecondsSinceEpoch(
              item['modifiedMillis'] as int,
            ),
            locationLabel: item['locationLabel'] as String,
            isEncrypted: item['isEncrypted'] as bool,
          ),
        )
        .toList(growable: false);
    final duplicateGroups = (decoded['duplicateGroups'] as List)
        .cast<Map<String, dynamic>>()
        .map(PdfDuplicateGroup.fromJson)
        .toList(growable: false);
    return NativePdfScanResult(
      files: files,
      duplicateGroups: duplicateGroups,
      stats: NativeScanStats.fromJson(
        decoded['stats'] as Map<String, dynamic>,
      ),
    );
  }

  static String _defaultLibraryName() {
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libarcpdf_indexer.so';
    }
    if (Platform.isMacOS || Platform.isIOS) return 'libarcpdf_indexer.dylib';
    if (Platform.isWindows) return 'arcpdf_indexer.dll';
    return p.join('.', 'libarcpdf_indexer.so');
  }
}
