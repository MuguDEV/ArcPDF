import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:arcpdf/src/features/pdf/home/widgets/pdf_thumbnail.dart';
import 'package:arcpdf/src/features/pdf/home/widgets/pdf_thumbnail_cache.dart';
import 'package:arcpdf/src/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shimmer/shimmer.dart';

class _Document extends Mock implements PdfDocument {}

class _Page extends Mock implements PdfPage {}

class _PdfImage extends Mock implements PdfImage {}

class _Box extends Mock implements Box<dynamic> {}

class _File extends Mock implements File {}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Backend extends Fake implements PdfrxEntryFunctions {
  final calls = <String>[];
  late Future<PdfDocument> Function(String) open;

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) {
    calls.add(filePath);
    return open(filePath);
  }
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Thumbnail work did not finish');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform originalPaths;
  late PdfrxEntryFunctions originalBackend;
  late _Backend backend;
  late String source;
  var serial = 0;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('arcpdf_thumbnails_');
    originalPaths = PathProviderPlatform.instance;
    originalBackend = PdfrxEntryFunctions.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPaths;
    PdfrxEntryFunctions.instance = originalBackend;
    await root.delete(recursive: true);
  });

  setUp(() {
    source = '${root.path}/source_${serial++}.pdf';
    backend = _Backend();
    PdfrxEntryFunctions.instance = backend;
  });

  File diskFile() => File('${root.path}/thumbnails/${source.hashCode}.png');

  _Document document({List<PdfPage> pages = const []}) {
    final doc = _Document();
    when(() => doc.pages).thenReturn(pages);
    when(() => doc.dispose()).thenAnswer((_) async {});
    return doc;
  }

  (_Document, _Page, _PdfImage) renderable({bool lowPower = false}) {
    final page = _Page();
    final pixels = _PdfImage();
    final width = lowPower ? 150.0 : 180.0;
    when(() => page.width).thenReturn(600);
    when(() => page.height).thenReturn(900);
    when(() => page.render(fullWidth: width, fullHeight: width * 1.5))
        .thenAnswer((_) async => pixels);
    when(() => pixels.width).thenReturn(2);
    when(() => pixels.height).thenReturn(3);
    when(() => pixels.pixels)
        .thenReturn(Uint8List.fromList(List.filled(24, 255)));
    return (document(pages: [page]), page, pixels);
  }

  group('cache', () {
    test('missing sources return null without opening PDF or disk cache',
        () async {
      final orphan = diskFile();
      await orphan.parent.create(recursive: true);
      await orphan.writeAsBytes([1, 2, 3]);
      expect(await PdfThumbnailCache.getThumbnail(source), isNull);
      expect(backend.calls, isEmpty);
    });

    test('coalesces requests and releases failed in-flight entries', () async {
      await File(source).writeAsString('pdf');
      final gate = Completer<PdfDocument>();
      backend.open = (_) => gate.future;
      final first = PdfThumbnailCache.getThumbnail(source);
      final second = PdfThumbnailCache.getThumbnail(source);
      expect(identical(first, second), isTrue);
      await _until(() => backend.calls.length == 1);
      gate.completeError(StateError('open failed'));
      expect(await first, isNull);
      expect(await second, isNull);

      final doc = document();
      backend.open = (_) async => doc;
      expect(await PdfThumbnailCache.getThumbnail(source), isNull);
      expect(backend.calls.length, 2);
      verify(() => doc.dispose()).called(1);
    });

    test('runs at most four native tasks and drains the queue after errors',
        () async {
      final paths = List.generate(9, (i) => '$source.$i');
      for (final path in paths) {
        await File(path).writeAsString('pdf');
      }
      final gates = <String, Completer<PdfDocument>>{};
      var active = 0;
      var maximum = 0;
      backend.open = (path) async {
        active++;
        if (active > maximum) maximum = active;
        final gate = gates[path] = Completer<PdfDocument>();
        try {
          return await gate.future;
        } finally {
          active--;
        }
      };
      final futures = paths.map(PdfThumbnailCache.getThumbnail).toList();
      await _until(() => gates.length == 4);
      expect(backend.calls.length, 4);
      for (final path in paths) {
        await _until(() => gates.containsKey(path));
        gates[path]!.completeError(StateError('bad PDF'));
      }
      expect(await Future.wait(futures), everyElement(isNull));
      expect(maximum, 4);
      expect(active, 0);
    });

    for (final lowPower in [false, true]) {
      test('renders a bounded image once (low power: $lowPower)', () async {
        await File(source).writeAsString('pdf');
        final (doc, page, pixels) = renderable(lowPower: lowPower);
        backend.open = (_) async => doc;
        final image = await PdfThumbnailCache.getThumbnail(source,
            lowPowerMode: lowPower);
        expect(image, isNotNull);
        expect(
            await PdfThumbnailCache.getThumbnail(source,
                lowPowerMode: lowPower),
            same(image));
        expect(backend.calls.length, 1);
        final width = lowPower ? 150.0 : 180.0;
        verify(() => page.render(fullWidth: width, fullHeight: width * 1.5))
            .called(1);
        verify(() => pixels.dispose()).called(1);
        verify(() => doc.dispose()).called(1);
        await _until(
            () => diskFile().existsSync() && diskFile().lengthSync() > 0);
      });
    }

    test('cleans up the document after render failure', () async {
      await File(source).writeAsString('pdf');
      final (doc, page, _) = renderable();
      when(() => page.render(fullWidth: 180, fullHeight: 270))
          .thenAnswer((_) async => throw StateError('render failed'));
      backend.open = (_) async => doc;
      expect(await PdfThumbnailCache.getThumbnail(source), isNull);
      verify(() => doc.dispose()).called(1);
    });

    test('cleans up native image and document after image conversion failure',
        () async {
      await File(source).writeAsString('pdf');
      final (doc, _, pixels) = renderable();
      when(() => pixels.pixels).thenThrow(StateError('pixels unavailable'));
      backend.open = (_) async => doc;
      expect(await PdfThumbnailCache.getThumbnail(source), isNull);
      verify(() => pixels.dispose()).called(1);
      verify(() => doc.dispose()).called(1);
    });

    test('corrupt disk entries are regenerated', () async {
      await File(source).writeAsString('pdf');
      final cached = diskFile();
      await cached.parent.create(recursive: true);
      await cached.writeAsBytes([1, 2, 3]);
      final (doc, _, _) = renderable();
      backend.open = (_) async => doc;
      expect(await PdfThumbnailCache.getThumbnail(source), isNotNull);
      await _until(() => cached.lengthSync() > 3);
      expect(backend.calls.length, 1);
    });

    test('disk images are decoded within the render budget without PDF work',
        () async {
      await File(source).writeAsString('pdf');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      final picture = recorder.endRecording();
      final original = await picture.toImage(400, 600);
      final bytes = await original.toByteData(format: ui.ImageByteFormat.png);
      final cached = diskFile();
      await cached.parent.create(recursive: true);
      await cached.writeAsBytes(bytes!.buffer.asUint8List());
      original.dispose();
      picture.dispose();
      final image = await PdfThumbnailCache.getThumbnail(source);
      expect(image!.width, 180);
      expect(image.height, 270);
      expect(backend.calls, isEmpty);
    });

    test('failed background writes do not fail thumbnails or escape as futures',
        () async {
      await File(source).writeAsString('pdf');
      // A directory at the PNG path forces the asynchronous write to fail.
      await Directory(diskFile().path).create(recursive: true);
      final (doc, _, _) = renderable();
      backend.open = (_) async => doc;
      final errors = <Object>[];
      await runZonedGuarded(() async {
        expect(await PdfThumbnailCache.getThumbnail(source), isNotNull);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, (error, _) => errors.add(error));
      expect(errors, isEmpty);
      expect(PdfThumbnailCache.getCached(source), isNotNull);
    });
  });

  group('widget', () {
    late SettingsController settings;
    late ProviderContainer container;

    setUp(() {
      final box = _Box();
      when(() => box.get(any(), defaultValue: any(named: 'defaultValue')))
          .thenAnswer((call) => call.namedArguments[#defaultValue]);
      when(() => box.put(any(), any())).thenAnswer((_) async {});
      settings = SettingsController(box);
      container = ProviderContainer(overrides: [
        settingsControllerProvider.overrideWith((ref) => settings),
      ]);
    });

    tearDown(() => container.dispose());

    Future<void> mount(WidgetTester tester,
        {String? path,
        bool encrypted = false,
        bool corrupted = false,
        bool reducedMotion = false,
        Brightness brightness = Brightness.light}) {
      return tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: Center(
              child: PdfThumbnail(
                path: path ?? source,
                isEncrypted: encrypted,
                isCorrupted: corrupted,
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets(
        'rebuilds retain the future and never check files synchronously',
        (tester) async {
      final file = _File();
      final exists = Completer<bool>();
      when(() => file.exists()).thenAnswer((_) => exists.future);
      when(() => file.existsSync()).thenThrow(StateError('sync IO in build'));
      await IOOverrides.runZoned(() async {
        await mount(tester);
        final first = tester
            .widget<FutureBuilder<ui.Image?>>(
                find.byType(FutureBuilder<ui.Image?>))
            .future;
        for (var i = 0; i < 5; i++) {
          await mount(tester,
              brightness: i.isEven ? Brightness.dark : Brightness.light);
          expect(
              tester
                  .widget<FutureBuilder<ui.Image?>>(
                      find.byType(FutureBuilder<ui.Image?>))
                  .future,
              same(first));
        }
        exists.complete(false);
        await tester.pumpAndSettle();
        await mount(tester);
        await tester.pumpAndSettle();
        expect(find.byType(Shimmer), findsNothing);
        expect(find.byType(RawImage), findsNothing);
        verify(() => file.exists()).called(1);
        verifyNever(() => file.existsSync());
        expect(tester.takeException(), isNull);
      }, createFile: (_) => file);
    });

    for (final mode in ['normal', 'low power', 'reduced motion']) {
      testWidgets('$mode loading respects motion preferences', (tester) async {
        await settings.setLowPowerMode(mode == 'low power');
        final file = _File();
        final exists = Completer<bool>();
        when(() => file.exists()).thenAnswer((_) => exists.future);
        await IOOverrides.runZoned(() async {
          await mount(tester, reducedMotion: mode == 'reduced motion');
          expect(find.byType(Shimmer),
              mode == 'normal' ? findsOneWidget : findsNothing);
          expect(tester.getSize(find.byType(PdfThumbnail)), const Size(52, 72));
          exists.complete(false);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }, createFile: (_) => file);
      });
    }

    testWidgets('slow I/O does not leave a perpetual animation running',
        (tester) async {
      final file = _File();
      final exists = Completer<bool>();
      when(() => file.exists()).thenAnswer((_) => exists.future);
      await IOOverrides.runZoned(() async {
        await mount(tester);
        await tester.pumpAndSettle();
        expect(exists.isCompleted, isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);
        exists.complete(false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, createFile: (_) => file);
    });

    testWidgets('path and render configuration changes replace the future',
        (tester) async {
      final file = _File();
      when(() => file.exists()).thenAnswer((_) async => false);
      await IOOverrides.runZoned(() async {
        await mount(tester);
        final first = tester
            .widget<FutureBuilder<ui.Image?>>(
                find.byType(FutureBuilder<ui.Image?>))
            .future;
        await mount(tester, path: '$source.other');
        final second = tester
            .widget<FutureBuilder<ui.Image?>>(
                find.byType(FutureBuilder<ui.Image?>))
            .future;
        expect(second, isNot(same(first)));
        await settings.setLowPowerMode(true);
        await tester.pump();
        final third = tester
            .widget<FutureBuilder<ui.Image?>>(
                find.byType(FutureBuilder<ui.Image?>))
            .future;
        expect(third, isNot(same(second)));
        await tester.pumpAndSettle();
        verify(() => file.exists()).called(3);
        expect(tester.takeException(), isNull);
      }, createFile: (_) => file);
    });

    testWidgets('locked and corrupt thumbnails do not start cache work',
        (tester) async {
      final file = _File();
      await IOOverrides.runZoned(() async {
        await mount(tester, encrypted: true);
        await mount(tester, corrupted: true);
        verifyNever(() => file.exists());
        expect(find.byType(FutureBuilder<ui.Image?>), findsNothing);
        expect(tester.takeException(), isNull);
      }, createFile: (_) => file);
    });
  });
}
