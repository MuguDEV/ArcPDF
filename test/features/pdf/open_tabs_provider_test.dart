import 'dart:io';

import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late OpenTabsNotifier notifier;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('arcpdf_tabs_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('tabs');
  });

  tearDown(() async {
    notifier.dispose();
    await box.close();
    await directory.delete(recursive: true);
  });

  PdfFileItem item(String name) {
    final file = File('${directory.path}/$name.pdf')..writeAsStringSync('pdf');
    return PdfFileItem.fromFile(file);
  }

  test('closing earlier tabs preserves the active document and saved index',
      () async {
    notifier = OpenTabsNotifier(box);
    final items = [item('a'), item('b'), item('c'), item('d')];
    for (final item in items) {
      notifier.openTab(item);
    }
    notifier.setActiveIndex(2);
    notifier.closeTab(0);
    expect(notifier.state.tabs[notifier.state.activeIndex].path, items[2].path);
    expect(notifier.state.activeIndex, 1);
    notifier.closeTab(2);
    expect(notifier.state.tabs[notifier.state.activeIndex].path, items[2].path);
    notifier.closeTab(0);
    expect(notifier.state.tabs.single.path, items[2].path);
    expect(notifier.state.activeIndex, 0);
    await box.flush();
    expect(box.get('activeIndex'), 0);
    expect(box.get('paths'), [items[2].path]);
  });

  test('closing the active tab selects its predecessor, or the first tab', () {
    notifier = OpenTabsNotifier(box);
    final items = [item('a'), item('b'), item('c')];
    for (final item in items) {
      notifier.openTab(item);
    }
    notifier.setActiveIndex(1);
    notifier.closeTab(1);
    expect(notifier.state.tabs[notifier.state.activeIndex].path, items[0].path);
    notifier.closeTab(0);
    expect(notifier.state.tabs.single.path, items[2].path);
    expect(notifier.state.activeIndex, 0);
    notifier.closeTab(0);
    expect(notifier.state.tabs, isEmpty);
    expect(notifier.state.activeIndex, 0);
  });

  test('reopening an existing path selects it without adding a duplicate', () {
    notifier = OpenTabsNotifier(box);
    final a = item('a');
    notifier.openTab(a);
    notifier.openTab(item('b'));
    notifier.openTab(a.copyWith(openedAt: DateTime.now()));
    expect(notifier.state.tabs.length, 2);
    expect(notifier.state.activeIndex, 0);
  });

  test('invalid close and selection indices leave state unchanged', () {
    notifier = OpenTabsNotifier(box);
    notifier.openTab(item('a'));
    final state = notifier.state;
    notifier.closeTab(-1);
    notifier.closeTab(1);
    notifier.setActiveIndex(-1);
    notifier.setActiveIndex(1);
    expect(notifier.state, same(state));
  });

  test('restore preserves active path when an earlier saved file is missing',
      () async {
    final a = item('a');
    final b = item('b');
    final c = item('c');
    await box.put(
        'paths', ['${directory.path}/missing.pdf', a.path, b.path, c.path]);
    await box.put('activeIndex', 2);
    notifier = OpenTabsNotifier(box);
    expect(notifier.state.activeIndex, 1);
    expect(notifier.state.tabs[notifier.state.activeIndex].path, b.path);
  });

  for (final savedIndex in [-1, 20]) {
    test('restore falls back to the first tab for saved index $savedIndex',
        () async {
      final a = item('a');
      await box.put('paths', [a.path]);
      await box.put('activeIndex', savedIndex);
      notifier = OpenTabsNotifier(box);
      expect(notifier.state.activeIndex, 0);
    });
  }

  test('restore falls back safely when the active file is missing', () async {
    final a = item('a');
    await box.put('paths', [a.path, '${directory.path}/missing.pdf']);
    await box.put('activeIndex', 1);
    notifier = OpenTabsNotifier(box);
    expect(notifier.state.tabs.single.path, a.path);
    expect(notifier.state.activeIndex, 0);
  });
}
