import 'dart:io';
import 'dart:ui';

import 'package:arcpdf/src/features/pdf/data/reflow_engine.dart';
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
}
