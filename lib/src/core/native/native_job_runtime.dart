import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _SubmitNative = Uint64 Function(Pointer<Utf8> request);
typedef _SubmitDart = int Function(Pointer<Utf8> request);
typedef _SnapshotNative = Pointer<Utf8> Function(Uint64 jobId);
typedef _SnapshotDart = Pointer<Utf8> Function(int jobId);
typedef _CancelNative = Bool Function(Uint64 jobId);
typedef _CancelDart = bool Function(int jobId);
typedef _ReleaseNative = Void Function(Uint64 jobId);
typedef _ReleaseDart = void Function(int jobId);
typedef _UpdateNative = Bool Function(Uint64 jobId, Pointer<Utf8> update);
typedef _UpdateDart = bool Function(int jobId, Pointer<Utf8> update);
typedef _CompleteNative = Bool Function(Uint64 jobId, Pointer<Utf8> completion);
typedef _CompleteDart = bool Function(int jobId, Pointer<Utf8> completion);
typedef _FreeNative = Void Function(Pointer<Utf8> value);
typedef _FreeDart = void Function(Pointer<Utf8> value);

enum NativeJobState {
  queued,
  running,
  completed,
  failed,
  cancelled;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

class NativeJobError {
  const NativeJobError({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final String code;
  final String message;
  final bool retryable;

  factory NativeJobError.fromJson(Map<String, dynamic> json) => NativeJobError(
        code: json['code'] as String,
        message: json['message'] as String,
        retryable: json['retryable'] as bool,
      );
}

class NativeJobSnapshot {
  const NativeJobSnapshot({
    required this.jobId,
    required this.kind,
    required this.state,
    required this.stage,
    required this.progress,
    required this.processed,
    required this.total,
    required this.error,
    required this.result,
  });

  final int jobId;
  final String kind;
  final NativeJobState state;
  final String stage;
  final double? progress;
  final int processed;
  final int? total;
  final NativeJobError? error;
  final Map<String, dynamic>? result;

  factory NativeJobSnapshot.fromJson(Map<String, dynamic> json) =>
      NativeJobSnapshot(
        jobId: json['jobId'] as int,
        kind: json['kind'] as String,
        state: NativeJobState.values.byName(json['state'] as String),
        stage: json['stage'] as String,
        progress: (json['progress'] as num?)?.toDouble(),
        processed: json['processed'] as int,
        total: json['total'] as int?,
        error: json['error'] == null
            ? null
            : NativeJobError.fromJson(json['error'] as Map<String, dynamic>),
        result: json['result'] as Map<String, dynamic>?,
      );
}

class NativeJobException implements Exception {
  const NativeJobException(this.error);
  final NativeJobError error;

  @override
  String toString() => 'NativeJobException(${error.code}): ${error.message}';
}

class NativeJobCancelledException implements Exception {
  const NativeJobCancelledException();
}

class NativeJobHandle {
  NativeJobHandle._(this._runtime, this.id);

  final NativeJobRuntime _runtime;
  final int id;

  bool cancel() => _runtime._cancel(id);
}

class NativeExternalJobContext {
  const NativeExternalJobContext._(this._runtime, this.handle);

  final NativeJobRuntime _runtime;
  final NativeJobHandle handle;

  void update({
    required String stage,
    double? progress,
    int processed = 0,
    int? total,
  }) {
    _runtime._updateJob(handle.id, {
      'stage': stage,
      'progress': progress,
      'processed': processed,
      'total': total,
    });
  }

  void checkCancelled() {
    final snapshot = _runtime._readSnapshot(handle.id);
    if (snapshot.state == NativeJobState.cancelled) {
      throw const NativeJobCancelledException();
    }
  }
}

class NativeJobRuntime {
  NativeJobRuntime._(DynamicLibrary library)
      : _submit = library.lookupFunction<_SubmitNative, _SubmitDart>(
          'arcpdf_job_submit_json',
        ),
        _snapshot = library.lookupFunction<_SnapshotNative, _SnapshotDart>(
          'arcpdf_job_snapshot_json',
        ),
        _cancel = library.lookupFunction<_CancelNative, _CancelDart>(
          'arcpdf_job_cancel',
        ),
        _release = library.lookupFunction<_ReleaseNative, _ReleaseDart>(
          'arcpdf_job_release',
        ),
        _update = library.lookupFunction<_UpdateNative, _UpdateDart>(
          'arcpdf_job_update_json',
        ),
        _complete = library.lookupFunction<_CompleteNative, _CompleteDart>(
          'arcpdf_job_complete_json',
        ),
        _free = library.lookupFunction<_FreeNative, _FreeDart>(
          'arcpdf_free_string',
        );

  final _SubmitDart _submit;
  final _SnapshotDart _snapshot;
  final _CancelDart _cancel;
  final _ReleaseDart _release;
  final _UpdateDart _update;
  final _CompleteDart _complete;
  final _FreeDart _free;

  static NativeJobRuntime? tryOpen({String? libraryPath}) {
    try {
      return NativeJobRuntime._(
        DynamicLibrary.open(libraryPath ?? defaultLibraryName()),
      );
    } on Object {
      return null;
    }
  }

  NativeJobHandle submit(Map<String, dynamic> command) {
    final request = jsonEncode(command).toNativeUtf8();
    try {
      final id = _submit(request);
      if (id == 0) {
        throw const FormatException('Native runtime rejected the command');
      }
      return NativeJobHandle._(this, id);
    } finally {
      calloc.free(request);
    }
  }

  Future<Map<String, dynamic>> executeExternal({
    required String operation,
    required Future<Map<String, dynamic>> Function(
      NativeExternalJobContext context,
    ) action,
    void Function(NativeJobHandle handle)? onHandle,
    void Function(NativeJobSnapshot event)? onEvent,
  }) async {
    final handle = submit({
      'kind': 'external',
      'payload': {'operation': operation},
    });
    onHandle?.call(handle);
    while (true) {
      final snapshot = _readSnapshot(handle.id);
      onEvent?.call(snapshot);
      if (snapshot.state == NativeJobState.running) break;
      if (snapshot.state == NativeJobState.cancelled) {
        _release(handle.id);
        throw const NativeJobCancelledException();
      }
      if (snapshot.state == NativeJobState.failed) {
        _release(handle.id);
        throw NativeJobException(snapshot.error!);
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final context = NativeExternalJobContext._(this, handle);
    try {
      final result = await action(context);
      context.checkCancelled();
      _completeJob(handle.id, {'result': result});
    } on NativeJobCancelledException {
      handle.cancel();
    } catch (error) {
      _completeJob(handle.id, {
        'error': {
          'code': 'operation_failed',
          'message': error.toString(),
          'retryable': true,
        },
      });
    }
    return wait(handle, onEvent: onEvent);
  }

  Future<Map<String, dynamic>> executeNativePdf({
    required Map<String, dynamic> request,
    void Function(NativeJobHandle handle)? onHandle,
    void Function(NativeJobSnapshot event)? onEvent,
  }) {
    final handle = submit({'kind': 'nativePdf', 'payload': request});
    onHandle?.call(handle);
    return wait(handle, onEvent: onEvent);
  }

  Future<Map<String, dynamic>> executeReflow({
    required Map<String, dynamic> request,
    void Function(NativeJobHandle handle)? onHandle,
    void Function(NativeJobSnapshot event)? onEvent,
  }) {
    final handle = submit({'kind': 'reflow', 'payload': request});
    onHandle?.call(handle);
    return wait(handle, onEvent: onEvent);
  }

  Future<Map<String, dynamic>> wait(
    NativeJobHandle handle, {
    void Function(NativeJobSnapshot event)? onEvent,
    Duration pollInterval = const Duration(milliseconds: 32),
  }) async {
    NativeJobSnapshot? previous;
    try {
      while (true) {
        final current = _readSnapshot(handle.id);
        if (previous == null ||
            previous.state != current.state ||
            previous.stage != current.stage ||
            previous.progress != current.progress ||
            previous.processed != current.processed) {
          onEvent?.call(current);
          previous = current;
        }
        switch (current.state) {
          case NativeJobState.completed:
            return current.result ?? const <String, dynamic>{};
          case NativeJobState.failed:
            throw NativeJobException(
              current.error ??
                  const NativeJobError(
                    code: 'unknown_native_error',
                    message: 'The native operation failed.',
                    retryable: true,
                  ),
            );
          case NativeJobState.cancelled:
            throw const NativeJobCancelledException();
          case NativeJobState.queued:
          case NativeJobState.running:
            await Future<void>.delayed(pollInterval);
        }
      }
    } finally {
      _release(handle.id);
    }
  }

  NativeJobSnapshot _readSnapshot(int id) {
    final pointer = _snapshot(id);
    if (pointer == nullptr) {
      throw StateError('Native runtime returned an empty snapshot');
    }
    try {
      final decoded = jsonDecode(pointer.toDartString());
      if (decoded is! Map<String, dynamic> || decoded['error'] != null) {
        throw StateError('Native runtime returned an invalid snapshot');
      }
      return NativeJobSnapshot.fromJson(decoded);
    } finally {
      _free(pointer);
    }
  }

  bool _updateJob(int id, Map<String, dynamic> update) {
    final pointer = jsonEncode(update).toNativeUtf8();
    try {
      return _update(id, pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  bool _completeJob(int id, Map<String, dynamic> completion) {
    final pointer = jsonEncode(completion).toNativeUtf8();
    try {
      return _complete(id, pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  static String defaultLibraryName() {
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libarcpdf_indexer.so';
    }
    if (Platform.isMacOS || Platform.isIOS) return 'libarcpdf_indexer.dylib';
    if (Platform.isWindows) return 'arcpdf_indexer.dll';
    return 'libarcpdf_indexer.so';
  }
}
