import 'dart:io';

import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'package:arcpdf/src/features/pdf/application/open_tabs_provider.dart';
import 'package:arcpdf/src/features/pdf/application/pdf_library_controller.dart';
import 'package:arcpdf/src/features/pdf/data/pdf_scanner_service.dart';
import 'package:arcpdf/src/features/pdf/data/reading_progress_repository.dart';
import 'package:arcpdf/src/features/pdf/domain/pdf_file_item.dart';
import 'package:arcpdf/src/features/pdf/viewer/pdf_viewer_screen.dart';
import 'package:arcpdf/src/features/pdf/viewer/reader_controls_sheet.dart';
import 'package:arcpdf/src/features/pdf/viewer/route_observer.dart';
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
  late List<MethodCall> platformCalls;

  setUpAll(() {
    registerFallbackValue(
        const ReadingViewport(page: 1, pageCount: 1, zoom: 1, x: 0.5, y: 0.5));
  });

  setUp(() {
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
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
    when(() => progress.saveViewport(any(), any())).thenAnswer((call) async {
      final path = call.positionalArguments[0] as String;
      final viewport = call.positionalArguments[1] as ReadingViewport;
      when(() => progress.getLastReadPage(path)).thenReturn(viewport.page);
      when(() => progress.getLastZoom(path)).thenReturn(viewport.zoom);
      when(() => progress.getLastViewport(path)).thenReturn(viewport);
    });
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
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.grey, brightness: brightness)),
        navigatorObservers: [pdfRouteObserver],
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
    // File IO completes outside the fake clock; its FutureBuilder continuation
    // still needs a pump inside the test zone.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byType(PdfViewer).evaluate().isNotEmpty ||
          find.text('Unable to open PDF').evaluate().isNotEmpty) {
        break;
      }
    }
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
    verifyNever(() => progress.saveViewport(any(), any()));
    await disposeViewer(tester);
  });

  testWidgets('real PDF restores progress and keeps reader actions consistent',
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
    expect(viewer.controller!.currentZoom, closeTo(1.5, 0.001));
    final colors = Theme.of(tester.element(find.byType(PdfViewer))).colorScheme;
    expect(viewer.params.backgroundColor, colors.surface);
    expect(viewer.params.scrollPhysics, isA<BouncingScrollPhysics>());
    expect(viewer.params.scrollPhysicsScale, isA<ClampingScrollPhysics>());
    expect(viewer.params.scrollByMouseWheel, 1);
    expect(viewer.params.maxImageBytesCachedOnMemory, 80 * 1024 * 1024);
    expect(viewer.params.pageDropShadow, isNull);
    expect(
        viewer.params.matchTextColor, colors.primary.withValues(alpha: 0.16));
    expect(viewer.params.activeMatchTextColor,
        colors.primary.withValues(alpha: 0.32));
    expect(viewer.controller!.pageNumber, 3); // Saved page 7 is clamped.
    final initialCheckpoint =
        verify(() => progress.saveViewport(file.path, captureAny()))
            .captured
            .last as ReadingViewport;
    expect(initialCheckpoint.page, 3);
    expect(initialCheckpoint.pageCount, 3);
    final originalDocument = viewer.controller!.document;
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    // Zoom gestures should not write Hive history on every rendered frame.
    await tester.pump(const Duration(milliseconds: 350));
    clearInteractions(progress);
    for (final zoom in [1.6, 1.7, 1.8]) {
      viewer.controller!.setZoom(viewer.controller!.centerPosition, zoom,
          duration: Duration.zero);
      await tester.pump(const Duration(milliseconds: 16));
    }
    verifyNever(() => progress.saveViewport(any(), any()));
    await tester.pump(const Duration(milliseconds: 350));
    final saved = verify(() => progress.saveViewport(file.path, captureAny()))
        .captured
        .single as ReadingViewport;
    expect(saved.zoom, closeTo(1.8, 0.001));
    expect(saved.pageCount, 3);

    // Auto-hide and document taps must never imply system fullscreen.
    platformCalls.clear();
    await tester.pump(const Duration(seconds: 5));
    expect(
        platformCalls.where(
            (call) => call.method == 'SystemChrome.setEnabledSystemUIMode'),
        isEmpty);
    Future<void> tapDocument() async {
      await tester.tapAt(const Offset(195, 450));
      // pdfrx distinguishes single taps from double-tap zoom gestures.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    }

    await tapDocument();
    final cachedViewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    await tapDocument();
    await tapDocument();
    expect(
        tester.widget<PdfViewer>(find.byType(PdfViewer)), same(cachedViewer));

    Future<void> selectFullscreen() async {
      await tester.tap(find.byTooltip('Reading controls'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester
          .ensureVisible(find.byKey(const ValueKey(ReaderAction.fullscreen)));
      await tester.tap(find.byKey(const ValueKey(ReaderAction.fullscreen)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    await selectFullscreen();
    expect(
        platformCalls
            .lastWhere(
                (call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
            .arguments,
        'SystemUiMode.immersiveSticky');

    await tapDocument();
    await selectFullscreen();
    expect(
        platformCalls
            .lastWhere(
                (call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
            .arguments,
        'SystemUiMode.edgeToEdge');
    platformCalls.clear();
    await tester.pump(const Duration(seconds: 5));
    await tapDocument();
    await tapDocument();
    expect(
        platformCalls.where(
            (call) => call.method == 'SystemChrome.setEnabledSystemUIMode'),
        isEmpty);
    await tapDocument();

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

    // Fullscreen belongs to the active reader, not covered routes or old tabs.
    await selectFullscreen();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered reader'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
        platformCalls
            .lastWhere(
                (call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
            .arguments,
        'SystemUiMode.edgeToEdge');
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
        platformCalls
            .lastWhere(
                (call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
            .arguments,
        'SystemUiMode.immersiveSticky');
    platformCalls.clear();
    await pumpViewer(tester, path: file.path, isActive: false);
    expect(
        platformCalls.where(
            (call) => call.method == 'SystemChrome.setEnabledSystemUIMode'),
        isEmpty);
    await pumpViewer(tester, path: file.path);
    expect(
        platformCalls
            .lastWhere(
                (call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
            .arguments,
        'SystemUiMode.immersiveSticky');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
        platformCalls
            .lastWhere(
                (call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
            .arguments,
        'SystemUiMode.immersiveSticky');
    expect(viewer.controller!.document, same(originalDocument));

    await pumpViewer(tester, path: file.path, isActive: false);
    clearInteractions(progress);
    await tester.pump(const Duration(seconds: 12));
    verifyNever(() => progress.addReadTime(any(), any()));
    final loadedDocument = viewer.controller!.document;
    platformCalls.clear();
    await disposeViewer(tester);
    expect(
        platformCalls.where(
            (call) => call.method == 'SystemChrome.setEnabledSystemUIMode'),
        isEmpty);
    await tester.runAsync(loadedDocument.dispose);
    // Drain pdfrx's trailing-page delay after native work has completed.
    await tester.pump(const Duration(seconds: 1));
    // PDFium can release its last Windows file handle on a trailing render
    // task, after document.dispose has already completed.
    for (var attempt = 0;; attempt++) {
      try {
        directory.deleteSync(recursive: true);
        break;
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 32 || attempt == 19) rethrow;
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fast flings travel farther across pages than slow swipes',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('arcpdf_fling_test');
    final file = File('${directory.path}/many_pages.pdf');
    final document = pdf.PdfDocument();
    for (var i = 0; i < 40; i++) {
      document.pages.add();
    }
    file.writeAsBytesSync(document.saveSync());
    document.dispose();
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.path;
    await tester.runAsync(pdfrxFlutterInitialize);
    await pumpViewer(tester, path: file.path);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final controller = viewer.controller!;
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(controller.isReady, isTrue);
    await tester.pump();

    Future<double> travel(double speed) async {
      await controller.goToPage(pageNumber: 10, duration: Duration.zero);
      await tester.pump();
      final start = controller.centerPosition.dy;
      await tester.flingFrom(
          const Offset(195, 650), const Offset(0, -220), speed);
      // Sample actual frames, not one giant fake-clock step.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return controller.centerPosition.dy - start;
    }

    final slow = await travel(700);
    final fast = await travel(6500);
    expect(slow, greaterThan(0));
    expect(fast, greaterThan(slow * 2));
    expect(fast, greaterThan(controller.layout.pageLayouts.first.height * 2));
    expect(tester.takeException(), isNull);
    final loaded = controller.document;
    await disposeViewer(tester);
    await tester.runAsync(loaded.dispose);
    await tester.pump(const Duration(seconds: 1));
    for (var attempt = 0;; attempt++) {
      try {
        directory.deleteSync(recursive: true);
        break;
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 32 || attempt == 19) rethrow;
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  });

  testWidgets(
      'leaving before the next frame saves page zoom and exact position',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('arcpdf_resume_test');
    final file = File('${directory.path}/resume.pdf');
    final document = pdf.PdfDocument();
    for (var i = 0; i < 5; i++) {
      document.pages.add();
    }
    file.writeAsBytesSync(document.saveSync());
    document.dispose();
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.path;
    await tester.runAsync(pdfrxFlutterInitialize);

    Future<PdfViewerController> open({bool active = true}) async {
      await pumpViewer(tester, path: file.path, isActive: active);
      final controller =
          tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
        if (controller.isReady && find.text('Not loaded').evaluate().isEmpty) {
          break;
        }
      }
      expect(controller.isReady, isTrue);
      return controller;
    }

    Future<void> close(PdfViewerController controller) async {
      final loaded = controller.document;
      await disposeViewer(tester);
      await tester.runAsync(loaded.dispose);
      await tester.pump(const Duration(seconds: 1));
    }

    final controller = await open();
    final rect = controller.layout.pageLayouts[2];
    final target =
        Offset(rect.left + rect.width * 0.6, rect.top + rect.height * 0.7);
    clearInteractions(progress);
    await controller.goTo(controller.calcMatrixFor(target, zoom: 2),
        duration: Duration.zero);
    // No pump: the coalesced controller listener has not captured this frame.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final saved = verify(() => progress.saveViewport(file.path, captureAny()))
        .captured
        .single as ReadingViewport;
    expect(saved.page, 3);
    expect(saved.pageCount, 5);
    expect(saved.zoom, closeTo(2, 0.001));
    expect(saved.x, closeTo(0.6, 0.001));
    expect(saved.y, closeTo(0.7, 0.001));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await close(controller);

    clearInteractions(progress);
    final reopened = await open();
    expect(reopened.pageNumber, 3);
    expect(reopened.currentZoom, closeTo(2, 0.001));
    expect((reopened.centerPosition - target).distance, lessThan(0.01));
    final restoredWrites =
        verify(() => progress.saveViewport(file.path, captureAny()))
            .captured
            .cast<ReadingViewport>();
    expect(restoredWrites, isNotEmpty);
    expect(restoredWrites.every((value) => value.page == 3), isTrue);
    await close(reopened);

    // Adjacent, preloaded tabs must not rewrite progress before selection.
    clearInteractions(progress);
    final inactive = await open(active: false);
    await close(inactive);
    verifyNever(() => progress.saveViewport(any(), any()));

    // A changed document count invalidates the old offset, not the saved page.
    when(() => progress.getLastViewport(file.path)).thenReturn(
        const ReadingViewport(page: 3, pageCount: 99, zoom: 2, x: 0.1, y: 0.1));
    final changed = await open();
    expect(changed.pageNumber, 3);
    expect(changed.currentZoom, closeTo(2, 0.001));
    final changedRect = changed.layout.pageLayouts[2];
    expect(changed.centerPosition.dy,
        isNot(closeTo(changedRect.top + changedRect.height * 0.1, 0.01)));
    await close(changed);

    // Invalid legacy values fall back to a valid first-page, fitted viewport.
    when(() => progress.getLastReadPage(file.path)).thenReturn(-9);
    when(() => progress.getLastZoom(file.path)).thenReturn(double.nan);
    when(() => progress.getLastViewport(file.path)).thenReturn(null);
    final corrupt = await open();
    expect(corrupt.pageNumber, 1);
    expect(corrupt.currentZoom.isFinite, isTrue);
    expect(corrupt.currentZoom, greaterThan(0));
    await close(corrupt);

    when(() => progress.getLastReadPage(file.path)).thenReturn(1);
    when(() => progress.getLastZoom(file.path)).thenReturn(1e100);
    when(() => progress.getLastViewport(file.path)).thenReturn(
        const ReadingViewport(
            page: 1, pageCount: 5, zoom: 1e100, x: 1e300, y: 1e300));
    final extreme = await open();
    expect(extreme.currentZoom, closeTo(extreme.maxScale, 0.001));
    expect(extreme.centerPosition.dx.isFinite, isTrue);
    expect(extreme.centerPosition.dy.isFinite, isTrue);
    expect(extreme.pageNumber, 1);
    clearInteractions(progress);
    await extreme.goToPage(pageNumber: 5, duration: Duration.zero);
    expect(extreme.pageNumber, 5);
    await close(extreme);
    final completedCheckpoint =
        verify(() => progress.saveViewport(file.path, captureAny()))
            .captured
            .last as ReadingViewport;
    expect(completedCheckpoint.page, 5);
    final completed = await open();
    expect(completed.pageNumber, 5);
    expect(completed.pageCount, 5);
    await close(completed);

    for (var attempt = 0;; attempt++) {
      try {
        directory.deleteSync(recursive: true);
        break;
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 32 || attempt == 19) rethrow;
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
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
        final context = tester.element(find.byType(PdfViewerScreen));
        final colors = Theme.of(context).colorScheme;
        expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            colors.surface);
        final bars = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .where((decoration) =>
                decoration.border is Border && decoration.color != null);
        expect(bars, isNotEmpty);
        expect(
            bars.every((bar) =>
                bar.color!.withValues(alpha: 1) == colors.surfaceContainerLow),
            isTrue);
        await disposeViewer(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
