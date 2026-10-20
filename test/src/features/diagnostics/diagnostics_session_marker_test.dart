import 'dart:convert';
import 'dart:io';

import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/features/diagnostics/diagnostics_session_marker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late List<String> events;
  var tick = 0;

  DiagnosticsSessionMarker marker({String version = '1.4.4'}) =>
      DiagnosticsSessionMarker(
        directory: () async => directory,
        appVersion: () async => version,
        clock: () => DateTime.utc(2026, 10, 20, 10, 0, tick++),
        observeLifecycle: false,
        logEvent: (name, fields) async => events.add(
            '$name ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}'),
      );

  Map<String, dynamic> readMarker() => jsonDecode(File(
          '${directory.path}${Platform.pathSeparator}${DiagnosticsSessionMarker.fileName}')
      .readAsStringSync()) as Map<String, dynamic>;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_marker_');
    events = [];
    tick = 0;
  });

  tearDown(() => directory.delete(recursive: true));

  test('first launch is unknown, not unclean', () async {
    final session = marker();
    final previous = await session.beginSession();
    await session.settled();

    expect(previous.status, PreviousSessionStatus.unknown);
    expect(previous.reason, DiagnosticsSessionMarker.noMarkerReason);
    expect(events, isEmpty);
    expect(readMarker()['state'], 'running');
    expect(readMarker()['version'], '1.4.4');
  });

  test('a session that never ended is reported unclean on next start',
      () async {
    final crashed = marker(version: '1.4.3');
    await crashed.beginSession();
    await crashed.settled();

    final next = marker();
    final previous = await next.beginSession();

    expect(previous.status, PreviousSessionStatus.unclean);
    expect(previous.version, '1.4.3');
    expect(events.single, startsWith('app.previous_session.unclean '));
    expect(events.single, contains('previousVersion=1.4.3'));
    expect(next.toReport()['previous_session'], 'unclean');
  });

  test('ending the session makes the next start clean and silent', () async {
    final first = marker();
    await first.beginSession();
    await first.endSession();
    await first.settled();
    expect(readMarker()['state'], 'ended');

    final previous = await marker().beginSession();
    expect(previous.status, PreviousSessionStatus.clean);
    expect(events, isEmpty);
  });

  test('backgrounding ends the session, resuming restarts it', () async {
    final session = marker();
    await session.beginSession();

    session.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await session.settled();
    expect(readMarker()['state'], 'running');

    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    await session.settled();
    expect(readMarker()['state'], 'ended');

    session.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await session.settled();
    expect(readMarker()['state'], 'running');

    session.didChangeAppLifecycleState(AppLifecycleState.detached);
    await session.settled();
    expect(readMarker()['state'], 'ended');
  });

  test('begin is idempotent', () async {
    final session = marker();
    final a = await session.beginSession();
    final b = await session.beginSession();
    expect(identical(a, b), isTrue);
  });

  test('a corrupt marker is unknown and is replaced', () async {
    File('${directory.path}${Platform.pathSeparator}${DiagnosticsSessionMarker.fileName}')
        .writeAsStringSync('{"state": "runn');
    final session = marker();
    final previous = await session.beginSession();
    await session.settled();

    expect(previous.status, PreviousSessionStatus.unknown);
    expect(previous.reason, DiagnosticsSessionMarker.unreadableReason);
    expect(events, isEmpty);
    expect(readMarker()['state'], 'running');
  });

  test('an unusable directory never throws', () async {
    final session = DiagnosticsSessionMarker(
      directory: () async => throw const FileSystemException('denied'),
      appVersion: () async => throw StateError('no plugin'),
      observeLifecycle: false,
      logEvent: (_, __) async {},
    );
    final previous = await session.beginSession();
    await session.endSession();
    expect(previous.status, PreviousSessionStatus.unknown);
    expect(session.isActive, isTrue);
  });

  test('stores no user data in the marker', () async {
    final session = marker();
    await session.beginSession();
    await session.settled();
    expect(readMarker().keys,
        unorderedEquals(['v', 'state', 'startedAt', 'updatedAt', 'version']));
  });

  test('the unclean event is written to the app log', () async {
    final hiveDir = await Directory.systemTemp.createTemp('arcpdf_marker_log_');
    Hive.init(hiveDir.path);
    try {
      await AppLogger.init();
      await AppLogger.clearLogs();
      File('${directory.path}${Platform.pathSeparator}${DiagnosticsSessionMarker.fileName}')
          .writeAsStringSync(jsonEncode({
        'v': 1,
        'state': 'running',
        'updatedAt': '2026-10-20T09:00:00.000Z',
        'version': '1.4.3',
      }));
      final session = DiagnosticsSessionMarker(
        directory: () async => directory,
        appVersion: () async => '1.4.4',
        observeLifecycle: false,
      );
      await session.beginSession();
      await AppLogger.flush();
      expect(
        AppLogger.getLogs().map((entry) => entry.message),
        contains(startsWith('app.previous_session.unclean ')),
      );
    } finally {
      await AppLogger.flush();
      await Hive.close();
      await hiveDir.delete(recursive: true);
    }
  });
}
