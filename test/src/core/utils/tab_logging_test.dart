import 'dart:io';

import 'package:arcpdf/src/core/utils/logger.dart';
import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> sessions;
  OpenTabsNotifier? notifier;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_tab_logging_');
    Hive.init(directory.path);
    await AppLogger.init();
    await AppLogger.clearLogs();
    sessions = await Hive.openBox<dynamic>('sessions');
  });

  tearDown(() async {
    notifier?.dispose();
    notifier = null;
    await AppLogger.flush();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  PdfFileItem item(String name) => PdfFileItem(
        path: '${directory.path}/$name.pdf',
        name: '$name.pdf',
        sizeBytes: 10,
        lastModified: DateTime(2026),
        locationLabel: 'Private documents',
      );

  test('records restore, open, activate and close without document identity',
      () async {
    notifier = OpenTabsNotifier(sessions);
    final first = item('confidential_budget');
    final second = item('confidential_contract');
    notifier!.openTab(first);
    notifier!.openTab(second);
    notifier!.setActiveIndex(0);
    notifier!.openTab(second);
    notifier!.closeTab(1);
    await AppLogger.flush();
    final output = await AppLogger.exportLogs();
    for (final event in [
      'tabs.restored',
      'tabs.opened',
      'tabs.activated',
      'tabs.closed'
    ]) {
      expect(output, contains(event));
    }
    expect(output, contains(AppLogger.documentId(first.path)));
    expect(output, isNot(contains('confidential')));
    expect(output, isNot(contains(directory.path)));
    expect(sessions.get('paths'), [first.path]);
  });

  test('corrupt sessions report errors without preventing provider creation',
      () async {
    await sessions.put('paths', 'invalid session containing document text');
    notifier = OpenTabsNotifier(sessions);
    expect(notifier!.state.tabs, isEmpty);
    expect(
        AppLogger.getLogs().first.message, startsWith('tabs.restore.failed'));
    expect(await AppLogger.exportLogs(), isNot(contains('document text')));
  });

  test('session write failures are observed instead of becoming async errors',
      () async {
    notifier = OpenTabsNotifier(sessions);
    await sessions.close();
    notifier!.openTab(item('private'));
    await AppLogger.flush();
    expect(notifier!.state.tabs, hasLength(1));
    expect(AppLogger.getLogs().map((e) => e.message),
        anyElement(startsWith('tabs.session_save.failed')));
  });
}
