import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

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

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level,
      'message': message,
      'stackTrace': stackTrace,
    };
  }

  factory LogEntry.fromMap(Map<dynamic, dynamic> map) {
    return LogEntry(
      timestamp: DateTime.parse(map['timestamp']),
      level: map['level'],
      message: map['message'],
      stackTrace: map['stackTrace'],
    );
  }
}

class AppLogger {
  static const String _boxName = 'app_logs';
  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  static Future<void> info(String message) async {
    await _log('INFO', message, null);
  }

  static Future<void> warning(String message) async {
    await _log('WARNING', message, null);
  }

  static Future<void> error(String message, [Object? error, StackTrace? stackTrace]) async {
    final fullMessage = error != null ? '$message: $error' : message;
    await _log('ERROR', fullMessage, stackTrace?.toString());
  }

  static Future<void> _log(String level, String message, String? stackTrace) async {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      stackTrace: stackTrace,
    );

    if (kDebugMode) {
      final timeStr = DateFormat('HH:mm:ss').format(entry.timestamp);
      debugPrint('[$timeStr] [$level] ${entry.message}');
      if (entry.stackTrace != null) {
        debugPrint(entry.stackTrace);
      }
    }

    if (_box != null) {
      await _box!.add(entry.toMap());
      if (_box!.length > 500) {
        // Remove the oldest log to maintain a max of 500
        await _box!.deleteAt(0);
      }
    }
  }

  static List<LogEntry> getLogs() {
    if (_box == null) return [];
    return _box!.values.map((e) => LogEntry.fromMap(e as Map)).toList().reversed.toList();
  }

  static Future<void> clearLogs() async {
    if (_box != null) {
      await _box!.clear();
    }
  }
}
