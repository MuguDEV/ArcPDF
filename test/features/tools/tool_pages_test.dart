import 'dart:async';

import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/features/tools/pages/merge_pdfs_page.dart';
import 'package:arcpdf/src/features/tools/pages/rearrange_pages_page.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:arcpdf/src/features/tools/tool_action_dialog.dart';
import 'package:arcpdf/src/features/tools/utils/run_tool_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockBox extends Mock implements Box<dynamic> {}

class _Document extends Mock implements rx.PdfDocument {}

void main() {
  Future<void> pumpWithSettings(WidgetTester tester, Widget child) async {
    final box = _MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsControllerProvider
            .overrideWith((ref) => SettingsController(box)),
      ],
      child: child,
    ));
  }

  PdfFileItem initialFile() => PdfFileItem(
      path: '/missing/initial.pdf',
      name: 'initial.pdf',
      sizeBytes: 10,
      lastModified: DateTime(2026),
      locationLabel: 'Tools');

  testWidgets('rearrange initializes its supplied source path', (tester) async {
    final document = _Document();
    when(() => document.pages).thenReturn([]);
    when(() => document.dispose()).thenAnswer((_) async {});
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: RearrangePagesPage(
      initialFile: initialFile(),
      openDocument: (path) async {
        opened = path;
        return document;
      },
    )));
    await tester.pump();
    expect(opened, '/missing/initial.pdf');
    expect(find.text('Change PDF'), findsOneWidget);
    expect(find.textContaining('No PDF selected'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    verify(() => document.dispose()).called(1);
  });

  testWidgets('rearrange disposes a document that opens after unmount',
      (tester) async {
    final document = _Document();
    when(() => document.dispose()).thenAnswer((_) async {});
    final completer = Completer<rx.PdfDocument>();
    await tester.pumpWidget(MaterialApp(
        home: RearrangePagesPage(
      initialFile: initialFile(),
      openDocument: (_) => completer.future,
    )));
    await tester.pumpWidget(const SizedBox());
    completer.complete(document);
    await tester.pump();
    verify(() => document.dispose()).called(1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('merge deduplicates inputs and uses adjusted reorder indices',
      (tester) async {
    final box = _MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsControllerProvider
            .overrideWith((ref) => SettingsController(box))
      ],
      child: const MaterialApp(
          home: MergePdfsPage(initialFiles: [
        '/missing/a.pdf',
        '/missing/b.pdf',
        '/missing/c.pdf',
        '/missing/a.pdf',
      ])),
    ));
    expect(tester.takeException(), isNull);
    var list =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    expect(list.itemCount, 3);
    list.onReorderItem!(0, 2);
    await tester.pump();
    expect(tester.getTopLeft(find.text('b')).dy,
        lessThan(tester.getTopLeft(find.text('c')).dy));
    expect(tester.getTopLeft(find.text('c')).dy,
        lessThan(tester.getTopLeft(find.text('a')).dy));
    list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    list.onReorderItem!(2, 0);
    await tester.pump();
    expect(tester.getTopLeft(find.text('a')).dy,
        lessThan(tester.getTopLeft(find.text('b')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading blocks back and exceptions dismiss it with a failure',
      (tester) async {
    final completer = Completer<String?>();
    await pumpWithSettings(
        tester,
        MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => runToolAction(context,
                              title: 'Working', action: () => completer.future),
                          child: const Text('Run')),
                    ))));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Working'), findsOneWidget);
    final dialogContext = tester.element(find.byType(ToolActionDialog));
    await Navigator.of(dialogContext).maybePop();
    await tester.pump();
    expect(find.text('Working'), findsOneWidget);
    completer.completeError(StateError('Output directory unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Working'), findsNothing);
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion does not pop a route pushed above loading',
      (tester) async {
    final completer = Completer<String?>();
    final key = GlobalKey<NavigatorState>();
    await pumpWithSettings(
        tester,
        MaterialApp(
          navigatorKey: key,
          home: Builder(
              builder: (context) => TextButton(
                    onPressed: () => runToolAction(context,
                        title: 'Working', action: () => completer.future),
                    child: const Text('Run'),
                  )),
        ));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    key.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other route'))));
    await tester.pumpAndSettle();
    completer.complete(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Other route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion after caller disposal does not use its context',
      (tester) async {
    final completer = Completer<String?>();
    final key = GlobalKey<NavigatorState>();
    await pumpWithSettings(
        tester,
        MaterialApp(
            navigatorKey: key, home: const Scaffold(body: Text('Home'))));
    final page = MaterialPageRoute<void>(
        builder: (context) => Scaffold(
                body: TextButton(
              onPressed: () => runToolAction(context,
                  title: 'Working', action: () => completer.future),
              child: const Text('Run'),
            )));
    key.currentState!.push(page);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    key.currentState!.removeRoute(page);
    await tester.pump(const Duration(milliseconds: 500));
    completer.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing output share is actionable and keeps the dialog open',
      (tester) async {
    await pumpWithSettings(
        tester,
        const MaterialApp(
            home: Scaffold(
                body: ToolActionDialog(
          title: 'Saved',
          message: 'Done',
          isLoading: false,
          outputPath: '/missing/output.pdf',
        ))));
    await tester.runAsync(() async {
      await tester.tap(find.text('Share'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to open or share'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
