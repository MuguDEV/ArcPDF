import 'dart:io';
import 'dart:ui';

import 'package:arcpdf/src/core/native/native_job_runtime.dart';
import 'package:arcpdf/src/features/pdf/data/reflow_engine.dart';
import 'package:arcpdf/src/features/pdf/data/reflow_ocr_service.dart';
import 'package:arcpdf/src/features/pdf/domain/reflow_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  late Directory temporary;
  late Directory cache;
  late String source;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('reflow_engine_test_');
    cache = Directory(p.join(temporary.path, 'cache'));
    source = p.join(temporary.path, 'structured.pdf');
    final document = PdfDocument();
    document.pageSettings.size = const Size(420, 600);
    document.pageSettings.margins.all = 0;
    final body = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final heading = PdfStandardFont(
      PdfFontFamily.helvetica,
      22,
      style: PdfFontStyle.bold,
    );
    for (var pageNumber = 1; pageNumber <= 3; pageNumber++) {
      final page = document.pages.add();
      page.graphics.drawString(
        'ArcPDF Engineering Report',
        body,
        bounds: const Rect.fromLTWH(24, 18, 240, 18),
      );
      page.graphics.drawString(
        'Layout Analysis $pageNumber',
        heading,
        bounds: const Rect.fromLTWH(24, 80, 330, 32),
      );
      page.graphics.drawString(
        'This paragraph wraps across',
        body,
        bounds: const Rect.fromLTWH(24, 140, 260, 18),
      );
      page.graphics.drawString(
        'two source lines without losing its page anchor.',
        body,
        bounds: const Rect.fromLTWH(24, 155, 330, 18),
      );
      page.graphics.drawString(
        'Metric                       Value',
        body,
        bounds: const Rect.fromLTWH(24, 220, 330, 18),
      );
      page.graphics.drawString(
        'Pages                        $pageNumber',
        body,
        bounds: const Rect.fromLTWH(24, 238, 330, 18),
      );
      page.graphics.drawString(
        'Page $pageNumber',
        body,
        bounds: const Rect.fromLTWH(180, 565, 80, 18),
      );
    }
    File(source).writeAsBytesSync(document.saveSync());
    document.dispose();
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('builds geometry blocks, removes running content, and reuses cache',
      () async {
    final engine = ReflowEngine(cacheDirectory: () async => cache);
    final first = await engine.load(source);

    expect(first.pageCount, 3);
    expect(first.engineVersion, ReflowEngine.engineVersion);
    expect(first.blocks.where((b) => b.type == ReflowBlockType.pageBreak),
        hasLength(3));
    expect(first.blocks.any((b) => b.text.contains('ArcPDF Engineering')),
        isFalse);
    expect(first.blocks.any((b) => b.text.contains('Page #')), isFalse);

    final heading = first.blocks.firstWhere(
      (block) => block.type == ReflowBlockType.heading,
    );
    expect(heading.anchor.page, 1);
    expect(heading.anchor.bounds, isNot(Rect.zero));
    expect(heading.glyphs, isNotEmpty);
    expect(heading.glyphs.first.fontName, isNotEmpty);
    expect(heading.glyphs.first.fontSize, greaterThan(0));
    expect(heading.glyphs.first.baseline,
        closeTo(heading.glyphs.first.bounds.bottom, .01));

    final paragraph = first.blocks.firstWhere(
      (block) => block.text.contains('This paragraph wraps'),
    );
    expect(paragraph.text, contains('two source lines'));
    expect(paragraph.anchor.page, 1);
    final table = first.blocks.firstWhere(
      (block) => block.type == ReflowBlockType.table,
    );
    expect(table.rows, hasLength(2));
    expect(table.rows.first, containsAll(<String>['Metric', 'Value']));

    final cacheFiles = cache.listSync().whereType<File>().toList();
    expect(cacheFiles, hasLength(1));
    final modified = cacheFiles.single.statSync().modified;
    final second = await engine.load(source);
    expect(second.toJson(), first.toJson());
    expect(cacheFiles.single.statSync().modified, modified);
  });

  test('cache key changes with analysis settings', () async {
    final engine = ReflowEngine(cacheDirectory: () async => cache);
    await engine.load(source);
    await engine.load(
      source,
      settings: const ReflowSettings(removeRepeatedHeaders: false),
    );
    expect(cache.listSync().whereType<File>(), hasLength(2));
  });

  group('OCR', () {
    late _FakeNative native;
    late _FakeOcr ocr;
    late ReflowEngine engine;

    setUp(() {
      native = _FakeNative();
      ocr = _FakeOcr();
      engine = ReflowEngine(
        cacheDirectory: () async => cache,
        nativeRuntime: native,
        ocrService: ocr,
      );
    });

    test('cache key and engine version are unchanged', () {
      expect(ReflowEngine.engineVersion, 4);
      expect(const ReflowSettings().cacheKey,
          'tables_figures_clean-running-content_ocr');
      expect(const ReflowSettings(enableOcr: false).cacheKey,
          'tables_figures_clean-running-content_no-ocr');
    });

    test('documents without scanned pages never call OCR', () async {
      native.pages = [];
      final result = await engine.loadWithStatus(source);
      expect(result.ocrStatus, ReflowOcrStatus.notNeeded);
      expect(ocr.calls, 0);
      expect(native.requests, hasLength(1));
      expect((await engine.load(source)).pageCount, 2);
    });

    test('recognized pages are merged with a second native run', () async {
      ocr.result = const OcrOk([
        {'page': 1}
      ]);
      final result = await engine.loadWithStatus(source);
      expect(result.ocrStatus, ReflowOcrStatus.completed);
      expect(native.requests, hasLength(2));
      expect(native.requests.last['ocrPages'], [
        {'page': 1}
      ]);
    });

    test('empty recognized text is reported without an error', () async {
      ocr.result = const OcrEmptyText([
        {'page': 1, 'lines': []}
      ]);
      final result = await engine.loadWithStatus(source);
      expect(result.ocrStatus, ReflowOcrStatus.emptyText);
      expect(result.ocrError, isNull);
    });

    test('OCR failures are surfaced and never cached as complete', () async {
      for (final entry in {
        OcrFailureKind.moduleMissing: ReflowOcrStatus.moduleMissing,
        OcrFailureKind.unsupportedDevice: ReflowOcrStatus.unsupported,
        OcrFailureKind.timeout: ReflowOcrStatus.failed,
        OcrFailureKind.failed: ReflowOcrStatus.failed,
        OcrFailureKind.cancelled: ReflowOcrStatus.cancelled,
      }.entries) {
        native.requests.clear();
        ocr.result = OcrFailure(OcrException(entry.key));
        final result = await engine.loadWithStatus(source);
        expect(result.ocrStatus, entry.value, reason: '${entry.key}');
        expect(result.ocrError?.kind, entry.key);
        expect(result.document.ocrPages, [1]);
        expect(native.requests, hasLength(1), reason: 'no second run');
      }
      expect((await engine.loadWithStatus(source)).needsOcr, isFalse);
    });

    test('moduleMissing needs OCR so the UI can prompt', () async {
      ocr.result = const OcrFailure(OcrException(OcrFailureKind.moduleMissing));
      expect((await engine.loadWithStatus(source)).needsOcr, isTrue);
    });

    test('OCR disabled skips recognition', () async {
      final result = await engine.loadWithStatus(
        source,
        settings: const ReflowSettings(enableOcr: false),
      );
      expect(result.ocrStatus, ReflowOcrStatus.disabled);
      expect(ocr.calls, 0);
    });

    test('closing the document mid OCR publishes nothing', () async {
      final token = OcrCancellationToken();
      ocr.onRecognize = token.cancel;
      ocr.result = const OcrOk([
        {'page': 1}
      ]);
      final result = await engine.loadWithStatus(source, cancellation: token);
      expect(result.ocrStatus, ReflowOcrStatus.cancelled);
      expect(native.requests, hasLength(1));
    });
  });
}

class _FakeNative extends Fake implements NativeJobRuntime {
  List<int> pages = [1];
  final requests = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> executeReflow({
    required Map<String, dynamic> request,
    void Function(NativeJobHandle handle)? onHandle,
    void Function(NativeJobSnapshot event)? onEvent,
  }) async {
    requests.add(request);
    return {
      'fileHash': 'h',
      'engineVersion': ReflowEngine.engineVersion,
      'settingsKey': request['settingsKey'],
      'pageCount': 2,
      'blocks': <Object?>[],
      'ocrPages': request.containsKey('ocrPages') ? <int>[] : pages,
    };
  }
}

class _FakeOcr extends ReflowOcrService {
  int calls = 0;
  OcrResult result = const OcrEmptyText([]);
  void Function()? onRecognize;

  @override
  Future<OcrResult> recognizePages(
    String path,
    List<int> pages, {
    void Function(OcrProgress progress)? onProgress,
    OcrCancellationToken? cancellation,
  }) async {
    calls++;
    onRecognize?.call();
    return result;
  }
}
