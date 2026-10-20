import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/core/utils/rotating_log_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('buffers diagnostics before initialization', () async {
    final directory =
        await Directory.systemTemp.createTemp('arcpdf_early_log_');
    Hive.init(directory.path);
    try {
      await AppLogger.info('early.startup');
      await AppLogger.init();
      await AppLogger.flush();
      expect(AppLogger.getLogs().single.message, 'early.startup');
      expect(await AppLogger.exportLogs(), contains('early.startup'));
    } finally {
      await AppLogger.flush();
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  group('persistent logger', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('arcpdf_logs_');
      Hive.init(directory.path);
      await AppLogger.init();
      await AppLogger.clearLogs();
    });

    tearDown(() async {
      await AppLogger.flush();
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('logging completes before disk writes, flush persists in order',
        () async {
      await AppLogger.info('first');
      await AppLogger.warning('second');
      expect(AppLogger.getLogs().map((e) => e.message), ['second', 'first']);
      expect(Hive.box<dynamic>('app_logs').length, 0);
      await AppLogger.flush();
      expect(Hive.box<dynamic>('app_logs').length, 2);
      final lines = const LineSplitter().convert(await AppLogger.exportLogs());
      expect(lines.map((line) => (jsonDecode(line) as Map)['message']),
          ['first', 'second']);
    });

    test('worker isolate logs reach the main persistent writer', () async {
      await Isolate.run(() async {
        await AppLogger.error('scanner.worker.failed',
            const FileSystemException('private document contents'));
      });
      final deadline = Stopwatch()..start();
      while (!AppLogger.getLogs().any(
              (entry) => entry.message.startsWith('scanner.worker.failed')) &&
          deadline.elapsedMilliseconds < 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final output = await AppLogger.exportLogs();
      expect(output, contains('scanner.worker.failed [FileSystemException]'));
      expect(output, isNot(contains('private document contents')));
    });

    test('reopens retained recent history and archive', () async {
      await AppLogger.info('prior.session');
      await AppLogger.flush();
      await Hive.close();
      await AppLogger.init();
      expect(AppLogger.getLogs().single.message, 'prior.session');
      expect(await AppLogger.exportLogs(), contains('prior.session'));
    });

    test('bounds viewer and Hive history but exports older file records',
        () async {
      for (var batch = 0; batch < 5; batch++) {
        for (var index = 0; index < 180; index++) {
          await AppLogger.event('action',
              fields: {'index': batch * 180 + index});
        }
        await AppLogger.flush();
      }
      expect(AppLogger.getLogs(), hasLength(AppLogger.maxEntries));
      expect(Hive.box<dynamic>('app_logs').length, AppLogger.maxEntries);
      final export = const LineSplitter().convert(await AppLogger.exportLogs());
      expect(export, hasLength(900));
      expect((jsonDecode(export.first) as Map)['message'], 'action index=0');
      expect((jsonDecode(export.last) as Map)['message'], 'action index=899');
    });

    test('bounds an overflowing queue and reports lost entries', () async {
      for (var index = 0; index < 1000; index++) {
        AppLogger.info('burst.$index');
      }
      expect(AppLogger.getLogs(), hasLength(AppLogger.maxEntries));
      await AppLogger.flush();
      final export = const LineSplitter().convert(await AppLogger.exportLogs());
      expect(export, hasLength(AppLogger.maxPendingEntries + 1));
      expect(export.last, contains('744 entries dropped'));
      expect(export, anyElement(contains('burst.999')));
    });

    test('redacts sensitive paths, identifiers and exception payloads',
        () async {
      await AppLogger.info('thumbnail for private financial report.pdf');
      await AppLogger.info(r'open C:\Users\Alice\secret.pdf');
      await AppLogger.info('open /storage/emulated/0/private.pdf');
      await AppLogger.info('token=abc password=hunter2 api_key=xyz');
      await AppLogger.info(
          'https://example.com/private?q=secret alice@example.com');
      await AppLogger.error(
          'document.failed',
          const FileSystemException('DOCUMENT TEXT AND PASSWORD'),
          StackTrace.fromString(
              '#0 read (C:\\Users\\Alice\\private.dart:3:1)'));
      final output = await AppLogger.exportLogs();
      for (final secret in [
        'private financial',
        'Alice',
        'secret.pdf',
        '/storage/',
        'abc',
        'hunter2',
        'xyz',
        'example.com',
        'DOCUMENT TEXT AND PASSWORD',
      ]) {
        expect(output, isNot(contains(secret)), reason: secret);
      }
      expect(output, contains('FileSystemException'));
      expect(output, contains('[path]'));
      expect(output, contains('[redacted]'));
    });

    test('event fields redact private data before formatting', () async {
      await AppLogger.event('action', fields: {
        'query': 'private multiword search',
        'password': 'multiword password',
        'outputPath': 'relative/private file.pdf',
        'documentName': 'private document title',
        'count': 3,
        'object': _PrivateObject(),
      });
      final message = AppLogger.getLogs().single.message;
      expect(message, contains('query=[redacted]'));
      expect(message, contains('password=[redacted]'));
      expect(message, contains('count=3'));
      expect(message, isNot(contains('multiword')));
      expect(message, isNot(contains('relative')));
      expect(message, isNot(contains('private document title')));
    });

    test('bounds oversized entries and uses opaque document IDs', () async {
      await AppLogger.error(
          'x' * 100000, null, StackTrace.fromString('y' * 100000));
      final entry = AppLogger.getLogs().single;
      expect(entry.message.length, lessThanOrEqualTo(2049));
      expect(entry.stackTrace!.length, lessThanOrEqualTo(4097));
      final id = AppLogger.documentId('/private/budget.pdf');
      expect(id, matches(RegExp(r'^[a-f0-9]{16}$')));
      expect(AppLogger.documentId('/private/budget.pdf'), id);
      expect(AppLogger.documentId('/private/other.pdf'), isNot(id));
    });

    test('clear removes recent history and every retained file', () async {
      await AppLogger.info('remove.me');
      await AppLogger.flush();
      final archive = Directory(AppLogger.storageDirectory!);
      expect(await archive.list().toList(), isNotEmpty);
      await AppLogger.clearLogs();
      expect(AppLogger.getLogs(), isEmpty);
      expect(Hive.box<dynamic>('app_logs').length, 0);
      expect(await archive.list().toList(), isEmpty);
      expect(await AppLogger.exportLogs(), isEmpty);
    });

    test('export and clear serialize with queued writes', () async {
      await AppLogger.info('before.clear');
      final export = AppLogger.exportLogs();
      final clear = AppLogger.clearLogs();
      await export;
      await clear;
      await AppLogger.info('after.clear');
      await AppLogger.flush();
      final output = await AppLogger.exportLogs();
      expect(output, contains('after.clear'));
      expect(output, isNot(contains('before.clear')));
      expect(Hive.box<dynamic>('app_logs').length, 1);
    });

    test('a disk failure after startup falls back to Hive and memory',
        () async {
      final root = Directory(AppLogger.storageDirectory!);
      await root.delete(recursive: true);
      await File(root.path).writeAsString('blocked');
      await AppLogger.info('after.disk.failure');
      await AppLogger.flush();
      expect(AppLogger.storageDirectory, isNull);
      expect(AppLogger.persistenceAvailable, isTrue);
      expect(await AppLogger.exportLogs(), contains('after.disk.failure'));
      expect(AppLogger.getLogs().map((entry) => entry.message),
          anyElement(contains('Diagnostic file write failed')));
    });

    test('malformed legacy records do not hide valid sanitized history',
        () async {
      await Hive.close();
      final box = await Hive.openBox<dynamic>('app_logs');
      await box.add({'invalid': true});
      await box.add(LogEntry(
              timestamp: DateTime.now(),
              level: 'INFO',
              message: 'legacy token=secretvalue')
          .toMap());
      await box.close();
      await AppLogger.init();
      expect(AppLogger.getLogs().single.message, 'legacy token=[redacted]');
      expect(Hive.box<dynamic>('app_logs').length, 1);
    });

    test('file backend failure does not interrupt logging or Hive', () async {
      await Hive.close();
      final blocker = File('${directory.path}/not_a_directory');
      await blocker.writeAsString('block');
      await AppLogger.init(directory: Directory(blocker.path));
      await AppLogger.info('still.operating');
      await AppLogger.flush();
      expect(AppLogger.persistenceAvailable, isTrue);
      expect(AppLogger.storageDirectory, isNull);
      expect(
          Hive.box<dynamic>('app_logs').values,
          anyElement(predicate(
              (dynamic entry) => entry['message'] == 'still.operating')));
      expect(await AppLogger.exportLogs(), contains('still.operating'));
    });
  });

  group('rotating file archive', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('arcpdf_rotation_');
    });

    tearDown(() async => directory.delete(recursive: true));

    test('rotates by encoded bytes, keeps order, and bounds disk use',
        () async {
      final archive =
          RotatingLogFile(directory, maxFileBytes: 18, fileCount: 3);
      await archive.initialize();
      await archive.append(List.generate(10, (index) => '$index:éé'));
      final files = await directory.list().where((f) => f is File).toList();
      expect(files, hasLength(3));
      for (final file in files.cast<File>()) {
        expect(await file.length(), lessThanOrEqualTo(18));
      }
      expect(const LineSplitter().convert(await archive.readAll()),
          ['4:éé', '5:éé', '6:éé', '7:éé', '8:éé', '9:éé']);
      final reopened =
          RotatingLogFile(directory, maxFileBytes: 18, fileCount: 3);
      await reopened.initialize();
      await reopened.append(['10:éé']);
      expect(await reopened.readAll(), endsWith('10:éé\n'));
      await reopened.clear();
      expect(await directory.list().toList(), isEmpty);
    });

    test('recovers a partial last line after an abrupt shutdown', () async {
      final file = File('${directory.path}/arcpdf.0.jsonl');
      await file.writeAsString('complete\npartial');
      final archive = RotatingLogFile(directory, maxFileBytes: 32);
      await archive.initialize();
      await archive.append(['next']);
      expect(await archive.readAll(), 'complete\nnext\n');
    });

    test('discards oversized segments and skips oversized individual entries',
        () async {
      final file = File('${directory.path}/arcpdf.0.jsonl');
      await file.writeAsString('x' * 64);
      final archive = RotatingLogFile(directory, maxFileBytes: 16);
      await archive.initialize();
      await archive.append(['y' * 64, 'kept']);
      expect(await archive.readAll(), 'kept\n');
      expect(await file.length(), lessThanOrEqualTo(16));
    });
  });
}

class _PrivateObject {
  @override
  String toString() => throw StateError('must not serialize provider values');
}
