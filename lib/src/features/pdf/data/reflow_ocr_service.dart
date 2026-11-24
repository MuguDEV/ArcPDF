import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why an OCR request did not produce text.
enum OcrFailureKind {
  moduleMissing,
  unsupportedDevice,
  cancelled,
  timeout,
  permissionDenied,
  invalidRequest,
  failed,
}

/// A structured OCR failure mapped from the native error codes.
class OcrException implements Exception {
  const OcrException(this.kind, [this.message = '', this.cause]);

  final OcrFailureKind kind;
  final String message;

  /// Native exception class name (details.cause), when provided.
  final String? cause;

  factory OcrException.fromPlatform(PlatformException error) {
    final details = error.details;
    final cause = details is Map ? details['cause']?.toString() : null;
    final kind = switch (error.code) {
      'ocr_module_missing' => OcrFailureKind.moduleMissing,
      'ocr_unsupported_device' => OcrFailureKind.unsupportedDevice,
      'ocr_cancelled' => OcrFailureKind.cancelled,
      'ocr_timeout' => OcrFailureKind.timeout,
      'ocr_permission_denied' => OcrFailureKind.permissionDenied,
      'ocr_invalid_request' => OcrFailureKind.invalidRequest,
      _ => OcrFailureKind.failed,
    };
    return OcrException(kind, error.message ?? '', cause);
  }

  @override
  String toString() => 'OcrException(${kind.name}'
      '${message.isEmpty ? '' : ': $message'})';
}

/// Outcome of [ReflowOcrService.recognizePages].
sealed class OcrResult {
  const OcrResult();
}

/// Recognition finished and at least one page contains text.
class OcrOk extends OcrResult {
  const OcrOk(this.pages);
  final List<Map<String, Object?>> pages;
}

/// Recognition finished normally but no page contained any text. This is not
/// an error.
class OcrEmptyText extends OcrResult {
  const OcrEmptyText(this.pages);
  final List<Map<String, Object?>> pages;
}

/// Recognition did not finish. No partial result is published.
class OcrFailure extends OcrResult {
  const OcrFailure(this.error);
  final OcrException error;
  OcrFailureKind get kind => error.kind;
}

/// Per-page progress of one OCR request.
@immutable
class OcrProgress {
  const OcrProgress({
    required this.page,
    required this.done,
    required this.total,
  });
  final int page;
  final int done;
  final int total;
}

/// Cooperative cancellation handle. Cancel when the document closes.
class OcrCancellationToken {
  bool _cancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void _listen(VoidCallback listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void _unlisten(VoidCallback listener) => _listeners.remove(listener);
}

class ReflowOcrService {
  ReflowOcrService({MethodChannel? channel, bool Function()? isAndroid})
      : _channel = channel ?? const MethodChannel('com.arcpdf.app/reflow_ocr'),
        _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final MethodChannel _channel;
  final bool Function() _isAndroid;
  final Map<String, void Function(OcrProgress)> _progress = {};
  var _handlerInstalled = false;
  var _counter = 0;
  final String _prefix = DateTime.now().microsecondsSinceEpoch.toString();

  /// Request ids are unique for this process and service instance.
  String _nextRequestId() => 'ocr-$_prefix-${_counter++}';

  Future<void> _handleNative(MethodCall call) async {
    if (call.method != 'progress') return;
    final args = call.arguments;
    if (args is! Map) return;
    final callback = _progress[args['requestId']];
    // Unknown or finished request ids are late callbacks and are dropped.
    if (callback == null) return;
    final page = args['page'];
    final done = args['done'];
    final total = args['total'];
    if (page is! int || done is! int || total is! int) return;
    callback(OcrProgress(page: page, done: done, total: total));
  }

  /// Recognizes [pages] (1-based). Never throws for OCR problems; failures are
  /// returned as [OcrFailure]. When [cancellation] is cancelled the call
  /// completes at once with a cancelled failure and native work is cancelled.
  Future<OcrResult> recognizePages(
    String path,
    List<int> pages, {
    void Function(OcrProgress progress)? onProgress,
    OcrCancellationToken? cancellation,
  }) async {
    if (pages.isEmpty) return const OcrEmptyText([]);
    if (!_isAndroid()) {
      return const OcrFailure(OcrException(
        OcrFailureKind.unsupportedDevice,
        'OCR is only available on Android',
      ));
    }
    if (cancellation?.isCancelled ?? false) {
      return const OcrFailure(OcrException(OcrFailureKind.cancelled));
    }
    if (!_handlerInstalled) {
      _channel.setMethodCallHandler(_handleNative);
      _handlerInstalled = true;
    }
    final requestId = _nextRequestId();
    final completer = Completer<OcrResult>();
    void finish(OcrResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    void onCancel() {
      finish(const OcrFailure(OcrException(OcrFailureKind.cancelled)));
      unawaited(_cancelNative(requestId));
    }

    _progress[requestId] = (value) {
      if (completer.isCompleted || (cancellation?.isCancelled ?? false)) {
        return;
      }
      onProgress?.call(value);
    };
    cancellation?._listen(onCancel);

    unawaited(() async {
      try {
        final result =
            await _channel.invokeListMethod<Object?>('recognizePages', {
          'requestId': requestId,
          'path': path,
          'pages': pages,
          'maxDimension': 2400,
        });
        final recognized = (result ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((page) =>
                page.map((key, value) => MapEntry(key.toString(), value)))
            .cast<Map<String, Object?>>()
            .toList(growable: false);
        if (cancellation?.isCancelled ?? false) {
          finish(const OcrFailure(OcrException(OcrFailureKind.cancelled)));
        } else if (_hasText(recognized)) {
          finish(OcrOk(recognized));
        } else {
          finish(OcrEmptyText(recognized));
        }
      } on MissingPluginException {
        finish(const OcrFailure(OcrException(
          OcrFailureKind.unsupportedDevice,
          'OCR platform channel is not available',
        )));
      } on PlatformException catch (error) {
        finish(OcrFailure(OcrException.fromPlatform(error)));
      } on Object catch (error) {
        finish(OcrFailure(
          OcrException(OcrFailureKind.failed, '', error.runtimeType.toString()),
        ));
      }
    }());

    try {
      return await completer.future;
    } finally {
      _progress.remove(requestId);
      cancellation?._unlisten(onCancel);
    }
  }

  static bool _hasText(List<Map<String, Object?>> pages) => pages.any((page) {
        final lines = page['lines'];
        if (lines is! List) return false;
        return lines.any((line) =>
            line is Map &&
            (line['text']?.toString().trim().isNotEmpty ?? false));
      });

  Future<void> _cancelNative(String requestId) async {
    try {
      await _channel.invokeMethod<void>('cancelOcr', {'requestId': requestId});
    } on Object {
      // Cancellation is best effort. The result is already discarded.
    }
  }

  /// Cancels every native request. Call when the document closes.
  Future<void> cancelAll() async {
    if (!_isAndroid()) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on Object {
      // Best effort.
    }
  }
}
