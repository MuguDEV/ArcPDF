import 'dart:io';

import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/data/reading_progress_repository.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/viewer/pdf_viewer_screen.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:arcpdf/src/shared/widgets/arc_bouncy_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockBox extends Mock implements Box<dynamic> {}

class _MockProgress extends Mock implements ReadingProgressRepository {}

class _MockTypedBox<T> extends Mock implements Box<T> {}

class _MockScanner extends Mock implements PdfScannerService {}

void main() {
  late _MockProgress progress;
  late ProviderContainer container;

  setUp(() {
    final box = _MockBox();
    when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((call) => call.namedArguments[#defaultValue]);
    when(() => box.put(any(), any())).thenAnswer((_) async {});
    progress = _MockProgress();
    when(() => progress.getLastReadPage(any())).thenReturn(7);
    when(() => progress.getLastZoom(any())).thenReturn(1.5);
    when(() => progress.saveLastZoom(any(), any())).thenAnswer((_) async {});
    when(() => progress.saveLastReadPage(any(), any()))
        .thenAnswer((_) async {});
    when(() => progress.addReadTime(any(), any())).thenAnswer((_) async {});
    container = ProviderContainer(overrides: [
      settingsControllerProvider.overrideWith((ref) => SettingsController(box)),
      readingProgressRepositoryProvider.overrideWithValue(progress),
      openTabsProvider.overrideWith((ref) => OpenTabsNotifier(box)),
      pdfLibraryControllerProvider.overrideWith((ref) {
        final favorites = _MockTypedBox<String>();
        final recents = _MockTypedBox<String>();
        final timestamps = _MockTypedBox<int>();
        final tags = _MockTypedBox<List<String>>();
        when(() => favorites.keys).thenReturn([]);
        when(() => favorites.values).thenReturn([]);
        when(() => recents.keys).thenReturn([]);
        when(() => recents.values).thenReturn([]);
        when(() => timestamps.toMap()).thenReturn({});
        when(() => tags.keys).thenReturn([]);
        final scanner = _MockScanner();
        when(() => scanner.scan(
                requestPermission: any(named: 'requestPermission')))
            .thenAnswer((_) async => const ScanResult(
                files: [], permissionStatus: StoragePermissionStatus.granted));
        return PdfLibraryController(
            scanner, favorites, recents, timestamps, tags);
      }),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpViewer(
    WidgetTester tester, {
    String? path,
    bool isActive = true,
    double width = 390,
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = PdfFileItem(
      path: path ?? '/arcpdf_missing_viewer_test/document.pdf',
      name: 'A very long PDF document name that should not overflow.pdf',
      sizeBytes: 100,
      lastModified: DateTime(2026),
      locationLabel: 'Documents',
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: PdfViewerScreen(item: item, isActive: isActive),
      ),
    ));
    await tester.pump();
  }

  Future<void> disposeViewer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('opening a PDF does not initialize search before attachment',
      (tester) async {
    // This crashed in initState even for a missing file because the searcher
    // dereferenced its unattached controller before the first build.
    await pumpViewer(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Unable to open PDF'), findsOneWidget);
    expect(find.text('Back to library'), findsOneWidget);
    final search = tester.widget<ArcBouncyButton>(
      find.byWidgetPredicate((widget) =>
          widget is ArcBouncyButton && widget.tooltip == 'Search document'),
    );
    expect(search.onPressed, isNull);
    await disposeViewer(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable document keeps recovery controls visible and does not record reading',
      (tester) async {
    await pumpViewer(tester);
    await tester.pump(const Duration(seconds: 20));
    expect(tester.takeException(), isNull);
    final opacity =
        tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.every((widget) => widget.opacity == 1), isTrue);
    verifyNever(() => progress.addReadTime(any(), any()));
    verifyNever(() => progress.saveLastReadPage(any(), any()));
    await disposeViewer(tester);
  });

  testWidgets('real PDF becomes ready before search is constructed',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('arcpdf_viewer_test');
    final file = File('${directory.path}/test.pdf');
    final document = pdf.PdfDocument();
    for (var i = 0; i < 3; i++) {
      document.pages.add().graphics.drawString(
            'ArcPDF searchable page ${i + 1}',
            pdf.PdfStandardFont(pdf.PdfFontFamily.helvetica, 18),
          );
    }
    file.writeAsBytesSync(document.saveSync());
    document.dispose();
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.path;

    await tester.runAsync(pdfrxFlutterInitialize);
    await pumpViewer(tester, path: file.path);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    // Native PDF loading runs outside Flutter's fake asynchronous clock.
    for (var i = 0; i < 100 && !viewer.controller!.isReady; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isNull);

    expect(viewer.controller!.isReady, isTrue);
    await tester.pump();
    final search = tester.widget<ArcBouncyButton>(
      find.byWidgetPredicate((widget) =>
          widget is ArcBouncyButton && widget.tooltip == 'Search document'),
    );
    expect(search.onPressed, isNotNull);
    expect(viewer.controller!.pageCount, 3);
    expect(viewer.controller!.pageNumber, 3); // Saved page 7 is clamped.
    final originalDocument = viewer.controller!.document;
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.tap(find.byTooltip('Reading controls'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Reading controls'), findsOneWidget);
    await tester.tap(find.text('Page colors'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(viewer.controller!.document, same(originalDocument));
    expect(viewer.controller!.pageNumber, 3);
    await tester.tap(find.byTooltip('Jump to page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextFormField), '9999');
    await tester.tap(find.widgetWithText(FilledButton, 'Go to page'));
    await tester.pump();
    expect(find.text('Enter a page from 1 to 3'), findsOneWidget);
    expect(viewer.controller!.pageNumber, 3);
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Go to page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AlertDialog), findsNothing);
    expect(viewer.controller!.pageNumber, 2);
    await tester.tap(find.byTooltip('Search document'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ArcPDF');
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0;
        i < 100 && find.byTooltip('Next search result').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byTooltip('Next search result'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<AnimatedOpacity>(find
                .ancestor(
                  of: find.byType(TextField),
                  matching: find.byType(AnimatedOpacity),
                )
                .first)
            .opacity,
        1);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    await pumpViewer(tester, path: file.path, isActive: false);
    clearInteractions(progress);
    await tester.pump(const Duration(seconds: 12));
    verifyNever(() => progress.addReadTime(any(), any()));
    final loadedDocument = viewer.controller!.document;
    await disposeViewer(tester);
    await tester.runAsync(loadedDocument.dispose);
    // Drain pdfrx's trailing-page delay after native work has completed.
    await tester.pump(const Duration(seconds: 1));
    directory.deleteSync(recursive: true);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 700.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'viewer fits ${width}px at 200% text in ${brightness.name} mode',
          (tester) async {
        await pumpViewer(tester,
            width: width, textScale: 2, brightness: brightness);
        expect(tester.takeException(), isNull);
        await disposeViewer(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
