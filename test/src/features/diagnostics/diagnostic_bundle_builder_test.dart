import 'dart:async';
import 'dart:convert';

import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/features/diagnostics/diagnostic_bundle_builder.dart';
import 'package:arcpdf/src/features/diagnostics/diagnostic_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

class ParsedBundle {
  final sections = <String, Map<String, String>>{};
  final logLines = <Map<String, dynamic>>[];
}

ParsedBundle parse(String content) {
  final parsed = ParsedBundle();
  Map<String, String>? current;
  var inLogs = false;
  for (final line in const LineSplitter().convert(content)) {
    if (line.startsWith('## ')) {
      inLogs = line == '## logs';
      current = parsed.sections[line.substring(3)] = {};
    } else if (inLogs && line.startsWith('{')) {
      parsed.logLines.add(jsonDecode(line) as Map<String, dynamic>);
    } else if (current != null && line.contains(': ')) {
      final split = line.indexOf(': ');
      current[line.substring(0, split)] = line.substring(split + 2);
    }
  }
  return parsed;
}

LogEntry entry(String message,
        {int minute = 0, String level = 'INFO', String? stack}) =>
    LogEntry(
      timestamp: DateTime.utc(2026, 10, 20, 9).add(Duration(seconds: minute)),
      level: level,
      message: message,
      stackTrace: stack,
    );

DiagnosticBundleBuilder fullBuilder({
  DiagnosticSectionSource? device,
  DiagnosticLogSource? logs,
  int maxBytes = DiagnosticBundleBuilder.defaultMaxBytes,
  Duration timeout = const Duration(seconds: 5),
}) =>
    DiagnosticBundleBuilder(
      app: () => {
        'name': 'ArcPDF',
        'version': '1.4.4',
        'build': '12',
        'mode': 'release',
        'flavor': 'default',
      },
      device: device ??
          () => {
                'platform': 'android',
                'manufacturer': 'Google',
                'model': 'Pixel 7',
                'os_version': '14',
                'sdk_int': 34,
                'locale': 'en-US',
              },
      view: () => {
        'logical_size': '412x915',
        'device_pixel_ratio': 2.625,
        'text_scale': 1.15,
      },
      settings: () => {'theme_mode': 'dark', 'low_power_mode': false},
      runtime: () => {
        'library_size_bucket': '51-200',
        'open_tabs_count': 3,
        'favorites_count': 7,
      },
      session: () => {'previous_session': 'unclean', 'tracking': 'active'},
      logs: logs ?? () => [entry('app.session.started')],
      clock: () => DateTime.utc(2026, 10, 20, 10, 15),
      maxBytes: maxBytes,
      sourceTimeout: timeout,
    );

void main() {
  test('produces every section in one parseable, correctly named file',
      () async {
    final bundle = await fullBuilder().build();
    final parsed = parse(bundle.content);

    expect(bundle.fileName, 'arcpdf-diagnostics-1.4.4-20261020T101500Z.txt');
    expect(bundle.content, startsWith('ArcPDF diagnostic bundle\n'));
    expect(parsed.sections.keys,
        ['app', 'device', 'display', 'settings', 'runtime', 'session', 'logs']);
    expect(parsed.sections['app'], containsPair('version', '1.4.4'));
    expect(parsed.sections['app'], containsPair('mode', 'release'));
    expect(parsed.sections['device'], containsPair('model', 'Pixel 7'));
    expect(parsed.sections['device'], containsPair('sdk_int', '34'));
    expect(parsed.sections['display'], containsPair('text_scale', '1.15'));
    expect(parsed.sections['settings'], containsPair('theme_mode', 'dark'));
    expect(parsed.sections['runtime'], containsPair('open_tabs_count', '3'));
    expect(parsed.sections['runtime'],
        containsPair('library_size_bucket', '51-200'));
    expect(parsed.sections['session'],
        containsPair('previous_session', 'unclean'));
    expect(parsed.sections['logs'], containsPair('entries_included', '1'));
    expect(parsed.logLines.single['message'], 'app.session.started');
    expect(bundle.unavailableSections, isEmpty);
    expect(bundle.truncated, isFalse);
    expect(bundle.bytes, utf8.encode(bundle.content));
  });

  test('file name stays safe for odd versions', () async {
    final bundle = await DiagnosticBundleBuilder(
      app: () => {'version': '1.0/../x y'},
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
    ).build();
    expect(
        bundle.fileName, 'arcpdf-diagnostics-1.0_.._x_y-20260102T030405Z.txt');
  });

  test('redacts paths, PINs, secrets, documents, emails and URLs', () async {
    final bundle = await fullBuilder(
      device: () => {
        'model': 'Pixel 7',
        'serialNumber': 'SN-ABC123',
        'userName': 'alice',
        'computerName': 'ALICE-PC',
        'advertisingId': 'ad-1111',
        'accountEmail': 'alice@example.com',
        'note': 'cache at /home/alice/.config/arcpdf/data.db',
        'vaultPin': '482913',
      },
      logs: () => [
        entry(r'Opened C:\Users\alice\Documents\Tax Return 2024.pdf',
            minute: 1),
        entry('saved to /storage/emulated/0/Download/secret-plan.pdf',
            minute: 2),
        entry('unlock failed pin=482913 password: hunter2abc token=abcDEF123',
            minute: 3),
        entry('contact bob@example.com via https://example.com/x?token=zzz',
            minute: 4),
        entry('auth Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig', minute: 5),
        entry('key blob ${'a1' * 40}', minute: 6),
        entry('failure',
            minute: 7,
            level: 'ERROR',
            stack: '#0 main (file:///C:/Users/alice/app/lib/x.dart:3:1)\n'
                '#1 run (package:arcpdf/src/x.dart:9:9)'),
      ],
    ).build();
    final text = bundle.content;

    for (final leak in [
      'alice',
      'ALICE',
      'Tax Return',
      'secret-plan',
      '482913',
      'hunter2',
      'abcDEF123',
      'bob@example.com',
      'example.com',
      'SN-ABC123',
      'ad-1111',
      '/storage/',
      r'C:\Users',
      'eyJhbGci',
      'a1a1a1a1',
      '.pdf',
    ]) {
      expect(text, isNot(contains(leak)), reason: 'leaked "$leak"');
    }
    expect(text, contains('Pixel 7'));
    expect(text, contains('package:arcpdf/src/x.dart:9:9'));
    final device = parse(text).sections['device']!;
    expect(device['serial_number'], '[redacted]');
    expect(device['user_name'], '[redacted]');
    expect(device['vault_pin'], '[redacted]');
  });

  test('sanitising is idempotent and keeps log lines single-line', () {
    for (final sample in [
      r'C:\Users\a b\c.pdf and /var/log/x',
      'pin=1234 password: x secret="y"',
      'https://a.b/c?d=e mail@x.org',
      'plain text with 2026-10-20T10:00:00Z',
      'token=[uri] pin=[redacted]',
    ]) {
      final once = DiagnosticSanitizer.text(sample);
      expect(DiagnosticSanitizer.text(once), once, reason: sample);
    }
    expect(DiagnosticSanitizer.text('line1\nline2\r\nforged: yes'),
        isNot(contains('\n')));
  });

  test('forged multi-line log text cannot add report sections', () async {
    final bundle = await fullBuilder(
      logs: () => [entry('ok\n## settings\nlow_power_mode: forged')],
    ).build();
    final parsed = parse(bundle.content);
    expect(
        parsed.sections['settings'], containsPair('low_power_mode', 'false'));
    expect(parsed.logLines, hasLength(1));
  });

  group('size cap', () {
    test('keeps the newest entries within the limit', () async {
      final logs = [
        for (var i = 0; i < 3000; i++)
          entry('event number $i ${'x' * 100}', minute: i),
      ];
      const cap = 50000;
      final bundle = await fullBuilder(logs: () => logs, maxBytes: cap).build();
      final parsed = parse(bundle.content);

      expect(utf8.encode(bundle.content).length, lessThanOrEqualTo(cap));
      expect(bundle.truncated, isTrue);
      expect(bundle.availableLogEntries, 3000);
      expect(bundle.includedLogEntries, lessThan(3000));
      expect(bundle.includedLogEntries, greaterThan(100));
      expect(parsed.logLines, hasLength(bundle.includedLogEntries));
      expect(
          parsed.logLines.first['message'], startsWith('event number 2999 '));
      expect(bundle.content, isNot(contains('event number 0 ')));
      expect(parsed.sections['logs'], containsPair('truncated', 'true'));
      expect(parsed.sections['app'], containsPair('version', '1.4.4'));
    });

    test('default cap is 1 MB even for huge archives of multibyte text',
        () async {
      final logs = [
        for (var i = 0; i < 4000; i++)
          entry('${'😀' * 400} $i', minute: i, stack: 'frame ${'é' * 3000}'),
      ];
      final bundle = await fullBuilder(logs: () => logs).build();
      expect(
          utf8.encode(bundle.content).length, lessThanOrEqualTo(1024 * 1024));
      expect(bundle.truncated, isTrue);
    });

    test('never exceeds the cap even when the header alone is too large',
        () async {
      final bundle = await DiagnosticBundleBuilder(
        app: () => {for (var i = 0; i < 64; i++) 'k$i': 'v' * 250},
        logs: () => [entry('x')],
        maxBytes: DiagnosticBundleBuilder.minBytes,
      ).build();
      expect(utf8.encode(bundle.content).length,
          lessThanOrEqualTo(DiagnosticBundleBuilder.minBytes));
    });
  });

  group('graceful degradation', () {
    test('a throwing device source only affects the device section', () async {
      final bundle = await fullBuilder(
        device: () => throw StateError(r'C:\Users\alice\secret.db'),
      ).build();
      final parsed = parse(bundle.content);

      expect(parsed.sections['device'],
          {'status': 'unavailable', 'reason': 'StateError'});
      expect(bundle.content, isNot(contains('alice')));
      expect(bundle.unavailableSections, ['device']);
      expect(parsed.sections['app'], containsPair('version', '1.4.4'));
      expect(parsed.sections['runtime'], containsPair('favorites_count', '7'));
      expect(parsed.logLines, isNotEmpty);
    });

    test('async failures, timeouts and failing logs are contained', () async {
      final bundle = await DiagnosticBundleBuilder(
        app: () async => throw const FormatException('boom'),
        device: () => Completer<Map<String, Object?>>().future,
        logs: () => throw StateError('no archive'),
        sourceTimeout: const Duration(milliseconds: 20),
      ).build();
      final parsed = parse(bundle.content);

      expect(parsed.sections['app'], containsPair('reason', 'FormatException'));
      expect(parsed.sections['device'],
          containsPair('reason', 'TimeoutException'));
      expect(parsed.sections['logs'], containsPair('entries_included', '0'));
      expect(bundle.unavailableSections,
          containsAll(['app', 'device', 'logs', 'settings']));
      expect(bundle.fileName, startsWith('arcpdf-diagnostics-unknown-'));
    });
  });
}
