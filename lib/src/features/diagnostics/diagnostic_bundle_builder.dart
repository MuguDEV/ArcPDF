import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/utils/logger.dart';
import 'diagnostic_sanitizer.dart';

/// Supplies the key/value fields of one report section. Values should be
/// scalars (or short lists of scalars); anything else is rendered as its type.
typedef DiagnosticSectionSource = FutureOr<Map<String, Object?>> Function();

/// Supplies log entries in any order; the builder sorts newest first.
typedef DiagnosticLogSource = FutureOr<Iterable<LogEntry>> Function();

/// A finished, ready-to-share bug report.
class DiagnosticBundle {
  const DiagnosticBundle({
    required this.fileName,
    required this.content,
    required this.includedLogEntries,
    required this.availableLogEntries,
    required this.truncated,
    required this.unavailableSections,
  });

  final String fileName;
  final String content;
  final int includedLogEntries;
  final int availableLogEntries;

  /// True when older log entries were dropped to respect the size cap.
  final bool truncated;

  /// Names of sections whose source failed (they still appear in the file,
  /// marked `status: unavailable`).
  final List<String> unavailableSections;

  Uint8List get bytes => Uint8List.fromList(utf8.encode(content));
}

/// Builds the single-file bug report: header, then `## section` blocks of
/// `key: value` lines, then the redacted recent logs as JSON Lines, newest
/// first, until [maxBytes] is reached.
///
/// Pure and injectable: every data source is a function, so tests (and any
/// platform without a given plugin) can substitute their own. A source that
/// throws or times out only degrades its own section.
class DiagnosticBundleBuilder {
  DiagnosticBundleBuilder({
    this.app,
    this.device,
    this.view,
    this.settings,
    this.runtime,
    this.session,
    this.logs,
    DateTime Function()? clock,
    this.maxBytes = defaultMaxBytes,
    this.sourceTimeout = const Duration(seconds: 5),
  })  : assert(maxBytes >= minBytes),
        _clock = clock ?? DateTime.now;

  static const formatVersion = 1;
  static const defaultMaxBytes = 1024 * 1024;
  static const minBytes = 512;

  final DiagnosticSectionSource? app;
  final DiagnosticSectionSource? device;
  final DiagnosticSectionSource? view;
  final DiagnosticSectionSource? settings;
  final DiagnosticSectionSource? runtime;
  final DiagnosticSectionSource? session;
  final DiagnosticLogSource? logs;
  final int maxBytes;
  final Duration sourceTimeout;
  final DateTime Function() _clock;

  static final _fileNamePart = RegExp(r'[^A-Za-z0-9.\-]');

  Future<DiagnosticBundle> build() async {
    final now = _clock().toUtc();
    final unavailable = <String>[];

    Future<List<MapEntry<String, String>>> section(
        String name, DiagnosticSectionSource? source) async {
      if (source == null) {
        unavailable.add(name);
        return [const MapEntry('status', 'unavailable')];
      }
      try {
        final raw = await Future<Map<String, Object?>>.sync(source)
            .timeout(sourceTimeout);
        return _fields(raw);
      } catch (error) {
        unavailable.add(name);
        // Only the exception type: its message may carry paths or data.
        return [
          const MapEntry('status', 'unavailable'),
          MapEntry(
              'reason', DiagnosticSanitizer.text(error.runtimeType.toString())),
        ];
      }
    }

    final appFields = await section('app', app);
    final deviceFields = await section('device', device);
    final viewFields = await section('display', view);
    final settingsFields = await section('settings', settings);
    final runtimeFields = await section('runtime', runtime);
    final sessionFields = await section('session', session);

    final entries = await _readLogs(unavailable);

    final version = _versionOf(appFields);
    final fileName = 'arcpdf-diagnostics-$version-${_stamp(now)}.txt';

    final head = StringBuffer()
      ..writeln('ArcPDF diagnostic bundle')
      ..writeln('format: $formatVersion')
      ..writeln('generated_utc: ${now.toIso8601String()}')
      ..writeln('privacy: no document names, file paths, PINs, lock patterns, '
          'vault data, serial numbers or account identifiers are included; '
          'logs are redacted. Review before sharing.');
    void write(String title, List<MapEntry<String, String>> fields) {
      head
        ..writeln()
        ..writeln('## $title');
      for (final field in fields) {
        head.writeln('${field.key}: ${field.value}');
      }
    }

    write('app', appFields);
    write('device', deviceFields);
    write('display', viewFields);
    write('settings', settingsFields);
    write('runtime', runtimeFields);
    write('session', sessionFields);

    // Reserve room for the log section's own header/footer lines.
    const logHeaderReserve = 256;
    final headBytes = utf8.encode(head.toString()).length;
    var budget = maxBytes - headBytes - logHeaderReserve;

    final lines = <String>[];
    var included = 0;
    for (final entry in entries) {
      final line = _logLine(entry);
      final cost = utf8.encode(line).length + 1;
      if (cost > budget) break;
      budget -= cost;
      lines.add(line);
      included++;
    }
    final truncated = included < entries.length;

    final out = StringBuffer(head)
      ..writeln()
      ..writeln('## logs')
      ..writeln('order: newest first')
      ..writeln('encoding: jsonl')
      ..writeln('entries_included: $included')
      ..writeln('entries_available: ${entries.length}')
      ..writeln('truncated: $truncated');
    for (final line in lines) {
      out.writeln(line);
    }

    return DiagnosticBundle(
      fileName: fileName,
      content: _capUtf8(out.toString(), maxBytes),
      includedLogEntries: included,
      availableLogEntries: entries.length,
      truncated: truncated,
      unavailableSections: List.unmodifiable(unavailable),
    );
  }

  Future<List<LogEntry>> _readLogs(List<String> unavailable) async {
    final source = logs;
    if (source == null) {
      unavailable.add('logs');
      return const [];
    }
    try {
      final entries = (await Future.sync(source).timeout(sourceTimeout))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    } catch (_) {
      unavailable.add('logs');
      return const [];
    }
  }

  List<MapEntry<String, String>> _fields(Map<String, Object?> raw) {
    final fields = <MapEntry<String, String>>[];
    final seen = <String>{};
    for (final entry in raw.entries) {
      if (entry.value == null) continue;
      final key = DiagnosticSanitizer.key(entry.key);
      if (!seen.add(key)) continue;
      fields.add(MapEntry(
        key,
        DiagnosticSanitizer.isSensitiveKey(key)
            ? '[redacted]'
            : DiagnosticSanitizer.value(entry.value),
      ));
      if (fields.length >= 64) break;
    }
    if (fields.isEmpty) fields.add(const MapEntry('status', 'empty'));
    return fields;
  }

  String _versionOf(List<MapEntry<String, String>> appFields) {
    for (final field in appFields) {
      if (field.key == 'version') {
        final safe = field.value.replaceAll(_fileNamePart, '_');
        return safe.isEmpty || safe.length > 32 ? 'unknown' : safe;
      }
    }
    return 'unknown';
  }

  static String _stamp(DateTime utc) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
        'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// One JSON object per line; a second sanitising pass guards the file even
  /// if an entry reached memory unredacted.
  static String _logLine(LogEntry entry) {
    final stack = entry.stackTrace;
    return jsonEncode({
      't': entry.timestamp.toUtc().toIso8601String(),
      'level': const ['INFO', 'WARNING', 'ERROR'].contains(entry.level)
          ? entry.level
          : 'INFO',
      'message': DiagnosticSanitizer.text(entry.message, limit: 2048),
      if (stack != null)
        'stack': DiagnosticSanitizer.text(stack, limit: 4096, multiline: true),
    });
  }

  /// Hard guarantee for the size cap, even for pathological headers.
  static String _capUtf8(String text, int maxBytes) {
    final bytes = utf8.encode(text);
    if (bytes.length <= maxBytes) return text;
    var end = maxBytes;
    // Do not cut inside a multi-byte sequence.
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
    return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
  }
}
