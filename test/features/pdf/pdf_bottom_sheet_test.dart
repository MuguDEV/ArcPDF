import 'dart:async';

import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/home/widgets/pdf_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _Box<T> extends Mock implements Box<T> {}

class _Scanner extends Mock implements PdfScannerService {}

class _Library extends PdfLibraryController {
  _Library(super.scanner, super.favorites, super.recents, super.timestamps,
      super.tags);
  late final deletion = Completer<bool>();
  int deleteCalls = 0;

  @override
  Future<bool> deleteFile(PdfFileItem item) {
    deleteCalls++;
    return deletion.future;
  }
}

void main() {
  late _Library library;
  late ProviderContainer container;
  final item = PdfFileItem(
    path: '/arcpdf_sheet_test/document.pdf',
    name: 'A long document name used to verify the sheet layout.pdf',
    sizeBytes: 1024,
    lastModified: DateTime(2026),
    locationLabel: 'Documents',
  );

  setUp(() {
    final scanner = _Scanner();
    when(() => scanner.scan(requestPermission: any(named: 'requestPermission')))
        .thenAnswer((_) async => const ScanResult(
            files: [], permissionStatus: StoragePermissionStatus.granted));
    final favorites = _Box<String>();
    final recents = _Box<String>();
    final timestamps = _Box<int>();
    final tags = _Box<List<String>>();
    when(() => favorites.keys).thenReturn([]);
    when(() => favorites.values).thenReturn([]);
    when(() => recents.keys).thenReturn([]);
    when(() => recents.values).thenReturn([]);
    when(() => timestamps.toMap()).thenReturn({});
    when(() => tags.keys).thenReturn([]);
    library = _Library(scanner, favorites, recents, timestamps, tags);
    final session = _Box<dynamic>();
    when(() => session.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    when(() => session.put(any(), any())).thenAnswer((_) async {});
    final tabs = OpenTabsNotifier(session)..openTab(item);
    container = ProviderContainer(overrides: [
      pdfLibraryControllerProvider.overrideWith((ref) => library),
      openTabsProvider.overrideWith((ref) => tabs),
    ]);
  });

  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester,
      {bool largeText = false, double keyboard = 0}) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(largeText ? 2 : 1),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Scaffold(
            body: Consumer(
                builder: (context, ref, _) => FilledButton(
                    onPressed: () => showPdfBottomSheet(context, ref, item),
                    child: const Text('Open actions')))),
      ),
    ));
    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Delete File'));
    await tester.tap(find.text('Delete File'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('actions scroll without overflow at 200% text with keyboard',
      (tester) async {
    await mount(tester, largeText: true, keyboard: 260);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Move to Secure Vault'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('delete uses controller and closes stale document tab on success',
      (tester) async {
    await mount(tester);
    await confirmDelete(tester);
    expect(library.deleteCalls, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    library.deletion.complete(true);
    await tester.pumpAndSettle();
    expect(container.read(openTabsProvider).tabs, isEmpty);
    expect(find.text('File deleted'), findsOneWidget);
    expect(find.text('TAGS'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed delete keeps the error and original sheet open',
      (tester) async {
    await mount(tester);
    await confirmDelete(tester);
    library.deletion.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Failed to delete file'), findsOneWidget);
    expect(container.read(openTabsProvider).tabs, hasLength(1));
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('TAGS'), findsOneWidget);
    expect(find.text('File deleted'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
