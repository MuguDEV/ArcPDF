import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show IsolateNameServer, RootIsolateToken;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'rotating_log_file.dart';

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.stackTrace,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level,
        'message': message,
        'stackTrace': stackTrace,
      };

  factory LogEntry.fromMap(Map<dynamic, dynamic> map) => LogEntry(
        timestamp: DateTime.parse(map['timestamp'] as String),
        level: map['level'] as String,
        message: map['message'] as String,
        stackTrace: map['stackTrace'] as String?,
      );
}

/// Local diagnostics, not an audit trail: the OS can kill the process without
/// delivering a lifecycle callback. Await [flush] at important boundaries.
///
/// Logging calls enqueue bounded, sanitized entries without waiting for disk.
/// Use static event names and non-sensitive scalar fields; never pass document
/// text, search queries, passwords, tokens, or annotation contents.
class AppLogger {
  static const maxEntries = 500;
  static const maxPendingEntries = 256;
  static const String _boxName = 'app_logs';
  static const _portName = 'arcpdf.diagnostics.main';
  static RawReceivePort? _isolatePort;
  static final _recent = ListQueue<LogEntry>();
  static final _pending = ListQueue<LogEntry>();
  static final String _sessionSalt =
      List.generate(16, (_) => Random.secure().nextInt(256)).join(',');
  static Box<dynamic>? _box;
  static RotatingLogFile? _archive;
  static Future<void>? _initializing;
  static Future<void>? _draining;
  static Future<void>? _clearing;
  static Future<void> _storageOperations = Future.value();
  static bool _initialized = false;
  static bool _maintenance = false;
  static int _dropped = 0;

  static bool get persistenceAvailable =>
      (_box?.isOpen ?? false) || _archive != null;
  static String? get storageDirectory => _archive?.directory.path;

  /// Safe to call repeatedly. Failure of either storage backend is isolated
  /// from the other and must not prevent the app from starting.
  static Future<void> init({Directory? directory}) {
    _installIsolateBridge();
    if (_initialized && (_box == null || _box!.isOpen)) return Future.value();
    return _initializing ??= _initialize(directory).whenComplete(() {
      _initializing = null;
    });
  }

  static Future<void> _initialize(Directory? directory) async {
    // Hive may have been closed by a test or an explicit application shutdown.
    if (_initialized) {
      await flush();
      _recent.clear();
      _pending.clear();
      _archive = null;
      _initialized = false;
    }
    final buffered = _recent.toList();
    _recent.clear();
    try {
      _box = await Hive.openBox<dynamic>(_boxName,
          compactionStrategy: (entries, deleted) => deleted > maxEntries);
      final keys = _box!.keys.toList();
      for (final key in keys.skip(max(0, keys.length - maxEntries))) {
        try {
          final entry = LogEntry.fromMap(_box!.get(key) as Map);
          _remember(_sanitizeEntry(entry));
        } catch (_) {
          // A malformed legacy record must not hide all remaining diagnostics.
        }
      }
      // Bound and sanitize legacy data, including previously persisted errors.
      await _box!.clear();
      await _box!.addAll(_recent.map((entry) => entry.toMap()));
    } catch (_) {
      _box = null;
      _storageFailure('Recent log storage unavailable');
    }
    for (final entry in buffered) {
      _remember(entry);
    }
    try {
      final boxPath = _box?.path;
      final root = directory ??
          Directory(
              '${boxPath == null ? (await getApplicationSupportDirectory()).path : File(boxPath).parent.path}${Platform.pathSeparator}diagnostics');
      final archive = RotatingLogFile(root);
      await archive.initialize();
      _archive = archive;
    } catch (_) {
      _archive = null;
      _storageFailure('Diagnostic file storage unavailable');
    }
    _initialized = true;
    _scheduleDrain();
  }

  /// Opaque per-process correlation ID. Neither filenames nor paths are stored.
  static String documentId(String path) => sha256
      .convert(utf8.encode('$_sessionSalt:$path'))
      .toString()
      .substring(0, 16);

  static Future<void> event(String name,
      {Map<String, Object?> fields = const {}}) {
    final details = fields.entries.take(16).map((entry) {
      final key = _redact(entry.key, 64);
      final privateField = RegExp(
              r'password|passphrase|passcode|token|secret|authorization|api.?key|path|filename|documentname|routename|query|search|content|annotation|email|^name$|^text$|^pin$|^pattern$|^uri$|^url$|^error$',
              caseSensitive: false)
          .hasMatch(entry.key);
      if (privateField) return '$key=[redacted]';
      final value = entry.value;
      // Never invoke an arbitrary object's toString (it may include PDF data).
      final scalar =
          value == null || value is String || value is num || value is bool
              ? '$value'
              : '<${value.runtimeType}>';
      return '$key=${_redact(scalar, 256)}';
    }).join(' ');
    return info(details.isEmpty ? name : '$name $details');
  }

  static Future<void> info(String message) => _log('INFO', message, null);
  static Future<void> warning(String message) => _log('WARNING', message, null);

  static Future<void> error(String message,
      [Object? error, StackTrace? stackTrace]) {
    // Exception messages often contain paths, passwords, URLs or document text.
    // Keep their type and stack frames, never their arbitrary string payload.
    return _log(
        'ERROR',
        error == null ? message : '$message [${error.runtimeType}]',
        stackTrace?.toString());
  }

  static Future<void> _log(String level, String message, String? stack) {
    final entry = _sanitizeEntry(LogEntry(
        timestamp: DateTime.now().toUtc(),
        level: level,
        message: message,
        stackTrace: stack));
    if (RootIsolateToken.instance == null) {
      final port = IsolateNameServer.lookupPortByName(_portName);
      if (port != null) {
        port.send(entry.toMap());
        return Future.value();
      }
    }
    _enqueue(entry);
    return Future.value();
  }

  static void _installIsolateBridge() {
    if (RootIsolateToken.instance == null || _isolatePort != null) return;
    final port = RawReceivePort((dynamic message) {
      try {
        if (message is Map) {
          _enqueue(_sanitizeEntry(LogEntry.fromMap(message)));
        }
      } catch (_) {
        // Ignore malformed cross-isolate records, never fail a worker's task.
      }
    })
      ..keepIsolateAlive = false;
    if (IsolateNameServer.registerPortWithName(port.sendPort, _portName)) {
      _isolatePort = port;
    } else {
      port.close();
    }
  }

  static void _enqueue(LogEntry entry) {
    _remember(entry);
    if (_pending.length == maxPendingEntries) {
      _pending.removeFirst();
      _dropped++;
    }
    _pending.addLast(entry);
    _scheduleDrain();
  }

  static LogEntry _sanitizeEntry(LogEntry entry) => LogEntry(
        timestamp: entry.timestamp,
        level: const ['INFO', 'WARNING', 'ERROR'].contains(entry.level)
            ? entry.level
            : 'INFO',
        message: _redact(entry.message, 2048),
        stackTrace:
            entry.stackTrace == null ? null : _redact(entry.stackTrace!, 4096),
      );

  static String _redact(String text, int limit) {
    // Bound work before regex processing, and neutralize control characters to
    // prevent forged multiline events. Stack frames retain their newlines.
    var safe = text.length > limit ? '${text.substring(0, limit)}…' : text;
    safe = safe.replaceAll(RegExp(r'[\x00-\x08\x0B-\x1F\x7F]'), ' ');
    safe = safe.replaceAll(
        RegExp(r'(?:https?|file|content)://[^\s)\]]+', caseSensitive: false),
        '[uri]');
    safe = safe.replaceAll(RegExp(r'[A-Za-z]:[\\/][^\r\n\t]+'), '[path]');
    safe = safe.replaceAll(
        RegExp(
            r'/(?:storage|sdcard|data|home|Users|private|tmp|var|mnt)/[^\r\n\t]+'),
        '[path]');
    safe = safe.replaceAll(
        RegExp(r'(?<=\bfor )[^\r\n]*\.pdf\b', caseSensitive: false),
        '[document]');
    safe = safe.replaceAll(
        RegExp(r'\b[^\s/\\:=]+\.pdf\b', caseSensitive: false), '[document]');
    safe = safe.replaceAll(
        RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
            caseSensitive: false),
        '[email]');
    safe = safe.replaceAll(
        RegExp(r'\bBearer\s+\S+', caseSensitive: false), 'Bearer [redacted]');
    safe = safe.replaceAllMapped(
        RegExp(
            r'\b(password|passwd|token|secret|api[_-]?key|authorization)\s*[:=]\s*\S+',
            caseSensitive: false),
        (match) => '${match[1]}=[redacted]');
    return safe;
  }

  static void _remember(LogEntry entry) {
    if (_recent.length == maxEntries) _recent.removeFirst();
    _recent.addLast(entry);
  }

  static void _storageFailure(String message) {
    _remember(LogEntry(
        timestamp: DateTime.now().toUtc(), level: 'WARNING', message: message));
    if (kDebugMode) debugPrint('ArcPDF diagnostics: $message');
  }

  static void _scheduleDrain() {
    if (!_initialized ||
        _maintenance ||
        _draining != null ||
        _pending.isEmpty) {
      return;
    }
    _draining = Future<void>(() async {
      try {
        while (_pending.isNotEmpty && !_maintenance) {
          final batch = _pending.toList();
          _pending.clear();
          if (_dropped > 0) {
            final notice = LogEntry(
                timestamp: DateTime.now().toUtc(),
                level: 'WARNING',
                message:
                    'Diagnostic queue overflow: $_dropped entries dropped');
            _dropped = 0;
            _remember(notice);
            batch.add(notice);
          }
          final box = _box;
          if (box != null && box.isOpen) {
            try {
              await box.addAll(batch.map((entry) => entry.toMap()));
              final excess = box.length - maxEntries;
              if (excess > 0) {
                await box.deleteAll(box.keys.take(excess).toList());
              }
              await box.flush();
            } catch (_) {
              _box = null;
              _storageFailure(
                  'Recent log write failed; using remaining storage');
            }
          }
          final archive = _archive;
          if (archive != null) {
            try {
              await archive
                  .append(batch.map((entry) => jsonEncode(entry.toMap())));
            } catch (_) {
              _archive = null;
              _storageFailure(
                  'Diagnostic file write failed; using remaining storage');
            }
          }
        }
      } finally {
        _draining = null;
        _scheduleDrain();
      }
    });
  }

  /// Wait for queued writes. Normally only needed at export/lifecycle boundaries.
  static Future<void> flush() async {
    await _storageOperations;
    _scheduleDrain();
    while (_draining != null) {
      await _draining;
    }
  }

  static List<LogEntry> getLogs() => _recent.toList().reversed.toList();

  /// Exports the entire retained rotating archive, not just the viewer's window.
  static Future<String> exportLogs() async {
    await flush();
    return _withStoragePaused(() async {
      try {
        final output = await _archive?.readAll();
        if (output != null && output.isNotEmpty) return output;
      } catch (_) {
        _storageFailure(
            'Diagnostic archive read failed; exporting recent logs');
      }
      return _recent.map((entry) => jsonEncode(entry.toMap())).join('\n');
    });
  }

  // Export and clear share the writer's gate, so rotation cannot race a file
  // snapshot or recreate an archive while the user is clearing it.
  static Future<T> _withStoragePaused<T>(Future<T> Function() operation) {
    final result = _storageOperations.then((_) async {
      _maintenance = true;
      try {
        await _draining;
        return await operation();
      } finally {
        _maintenance = false;
        _scheduleDrain();
      }
    });
    _storageOperations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<void> clearLogs() => _clearing ??= _clear().whenComplete(() {
        _clearing = null;
      });

  static Future<void> _clear() => _withStoragePaused(() async {
        _pending.clear();
        _recent.clear();
        _dropped = 0;
        Object? failure;
        StackTrace? failureStack;
        try {
          if (_box?.isOpen ?? false) {
            await _box!.clear();
            await _box!.flush();
          }
        } catch (error, stack) {
          failure = error;
          failureStack = stack;
        }
        // Always try both backends, even if the first one is unavailable.
        try {
          await _archive?.clear();
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
        if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      });
}
