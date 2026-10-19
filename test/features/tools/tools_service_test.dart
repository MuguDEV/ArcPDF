import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:arcpdf/src/features/tools/tools_service.dart';
import 'package:arcpdf/src/features/tools/utils/page_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:mocktail/mocktail.dart';
import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _Document extends Mock implements rx.PdfDocument {}

class _Page extends Mock implements rx.PdfPage {}

class _Image extends Mock implements rx.PdfImage {}

void main() {
  late Directory temp;
  late String source;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tools_test_');
    source = p.join(temp.path, 'source.pdf');
    final document = PdfDocument();
    for (var i = 1; i <= 3; i++) {
      final section = document.sections!.add();
      section.pageSettings.size = Size(200.0 + i * 20, 300.0 + i * 20);
      section.pageSettings.margins.all = 0;
      section.pages
          .add()
          .graphics
          .drawString('Page $i', PdfStandardFont(PdfFontFamily.helvetica, 12));
    }
    File(source).writeAsBytesSync(document.saveSync());
    document.dispose();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('selection is strict, bounded, ordered and deduplicated', () {
    expect(parsePageSelection('3, 1-2, 3', pageCount: 3), [3, 1, 2]);
    for (final input in [
      '',
      '1,',
      '1,no',
      '0,1',
      '3-1',
      '1-4',
      '-1',
      '1-999999999999999999999999999999999'
    ]) {
      expect(
          () => parsePageSelection(input, pageCount: 3), throwsFormatException,
          reason: input);
    }
  });

  test('rearrange preserves requested order, text and mixed page sizes',
      () async {
    final output = p.join(temp.path, 'reordered.pdf');
    expect(await ToolsService.rearrangePdf(source, output, [3, 1]), output);
    final document = PdfDocument(inputBytes: File(output).readAsBytesSync());
    try {
      expect(document.pages.count, 2);
      expect(document.pages[0].size, const Size(260, 360));
      expect(document.pages[1].size, const Size(220, 320));
      final text = PdfTextExtractor(document).extractText();
      expect(text.indexOf('Page 3'), lessThan(text.indexOf('Page 1')));
      expect(text, isNot(contains('Page 2')));
    } finally {
      document.dispose();
    }
  });

  test('invalid pages fail the entire operation without creating output',
      () async {
    final output = p.join(temp.path, 'invalid.pdf');
    for (final pages in [
      [1, 4],
      [0, 1],
      <int>[]
    ]) {
      expect(await ToolsService.rearrangePdf(source, output, pages), isNull);
      expect(File(output).existsSync(), isFalse);
    }
  });

  test('merge fails on missing sources instead of publishing partial output',
      () async {
    final output = p.join(temp.path, 'merged.pdf');
    expect(await ToolsService.mergePdfs([source, '$source.missing'], output),
        isNull);
    expect(File(output).existsSync(), isFalse);
    expect(await ToolsService.mergePdfs([], output), isNull);
  });

  test('merge retains source order and mixed sizes', () async {
    final output = p.join(temp.path, 'merged.pdf');
    expect(await ToolsService.mergePdfs([source, source], output), output);
    final document = PdfDocument(inputBytes: File(output).readAsBytesSync());
    try {
      expect(document.pages.count, 6);
      expect(document.pages[0].size, const Size(220, 320));
      expect(document.pages[2].size, const Size(260, 360));
      expect(document.pages[3].size, const Size(220, 320));
    } finally {
      document.dispose();
    }
  });

  test('exports refuse existing outputs and never overwrite the source',
      () async {
    final original = File(source).readAsBytesSync();
    expect(await ToolsService.rearrangePdf(source, source, [3]), isNull);
    expect(await ToolsService.mergePdfs([source, source], source), isNull);
    expect(File(source).readAsBytesSync(), original);
    expect(temp.listSync().whereType<Directory>(), isEmpty);
  });

  test('metadata explicitly supports staged in-place replacement', () async {
    expect(
        await ToolsService.editPdfMetadata(
            inputPath: source,
            outputPath: source,
            title: 'Updated',
            author: 'Author',
            subject: 'Subject',
            keywords: 'Keywords'),
        source);
    final info = await ToolsService.readPdfMetadata(source);
    expect(info?.title, 'Updated');
    expect(info?.author, 'Author');
    expect(await ToolsService.readPageCount(source), 3);
    expect(temp.listSync().whereType<Directory>(), isEmpty);
  });

  test('failed metadata copy leaves an existing destination untouched',
      () async {
    final output = p.join(temp.path, 'existing.pdf');
    File(output).writeAsStringSync('keep me');
    expect(
        await ToolsService.editPdfMetadata(
            inputPath: source,
            outputPath: output,
            title: '',
            author: '',
            subject: '',
            keywords: ''),
        isNull);
    expect(File(output).readAsStringSync(), 'keep me');
  });

  test('image conversion preserves order and supports BMP', () async {
    final first = p.join(temp.path, 'first.bmp');
    final second = p.join(temp.path, 'second.png');
    File(first)
        .writeAsBytesSync(img.encodeBmp(img.Image(width: 80, height: 60)));
    File(second)
        .writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 90)));
    final output = p.join(temp.path, 'images.pdf');
    expect(await ToolsService.imagesToPdf([first, second], output), output);
    final document = PdfDocument(inputBytes: File(output).readAsBytesSync());
    try {
      expect(document.pages.count, 2);
      expect(document.pages[0].size, const Size(80, 60));
      expect(document.pages[1].size, const Size(40, 90));
    } finally {
      document.dispose();
    }
    final missingOutput = p.join(temp.path, 'missing.pdf');
    expect(
        await ToolsService.imagesToPdf(
            [first, '$second.missing'], missingOutput),
        isNull);
    expect(File(missingOutput).existsSync(), isFalse);
    expect(await ToolsService.imagesToPdf([], missingOutput), isNull);
  });

  test('extraction writes every numbered page and disposes native resources',
      () async {
    final document = _Document();
    final pages = List.generate(3, (_) => _Page());
    final images = List.generate(3, (_) => _Image());
    when(() => document.pages).thenReturn(pages);
    when(() => document.dispose()).thenAnswer((_) async {});
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      final image = images[index];
      when(() => page.width).thenReturn(2);
      when(() => page.height).thenReturn(2);
      when(() => page.render(fullWidth: 2, fullHeight: 2))
          .thenAnswer((_) async => image);
      when(() => image.width).thenReturn(2);
      when(() => image.height).thenReturn(2);
      when(() => image.pixels)
          .thenReturn(Uint8List.fromList(List.filled(16, 255)));
    }
    final output = await ToolsService.pdfToImages(source, temp.path,
        openDocument: (_) async => document);
    expect(output, isNotNull);
    expect(
        Directory(output!)
            .listSync()
            .map((file) => p.basename(file.path))
            .toSet(),
        {'page_1.jpg', 'page_2.jpg', 'page_3.jpg'});
    for (final image in images) {
      verify(() => image.dispose()).called(1);
    }
    verify(() => document.dispose()).called(1);
  });

  test('render failure cannot publish partial images or compressed PDF',
      () async {
    final document = _Document();
    final page = _Page();
    when(() => document.pages).thenReturn([page]);
    when(() => document.dispose()).thenAnswer((_) async {});
    when(() => page.width).thenReturn(2);
    when(() => page.height).thenReturn(2);
    when(() => page.render(fullWidth: 2, fullHeight: 2))
        .thenAnswer((_) async => null);
    expect(
        await ToolsService.pdfToImages(source, temp.path,
            openDocument: (_) async => document),
        isNull);
    expect(temp.listSync().whereType<Directory>(), isEmpty);
    final output = p.join(temp.path, 'compressed.pdf');
    expect(
        await ToolsService.compressPdf(source, output,
            openDocument: (_) async => document),
        isNull);
    expect(File(output).existsSync(), isFalse);
    verify(() => document.dispose()).called(2);
  });

  test('invalid compression settings return without native rendering',
      () async {
    expect(await ToolsService.compressPdf(source, '$source.out', maxThreads: 0),
        isNull);
    expect(await ToolsService.compressPdf(source, '$source.out', quality: 101),
        isNull);
  });
}
