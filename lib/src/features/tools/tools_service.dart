import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'job_queue.dart';

class PdfMetadataInfo {
  final String title;
  final String author;
  final String subject;
  final String keywords;

  const PdfMetadataInfo({
    this.title = '',
    this.author = '',
    this.subject = '',
    this.keywords = '',
  });
}

class ToolsService {
  static Future<int> readPageCount(String inputPath) => Isolate.run(() {
        final document = syncfusion.PdfDocument(
            inputBytes: File(inputPath).readAsBytesSync());
        try {
          return document.pages.count;
        } finally {
          document.dispose();
        }
      });
  // Stage in the destination filesystem so a failed write never truncates the
  // source. Only explicit metadata overwrite may replace an existing file.
  static Future<String> save(List<int> bytes, String outputPath,
      {bool overwrite = false}) async {
    final output = File(outputPath);
    if (!overwrite && await output.exists()) {
      throw FileSystemException('Output already exists', outputPath);
    }
    final staging =
        await Directory(p.dirname(outputPath)).createTemp('.arcpdf_');
    try {
      final temp = File(p.join(staging.path, 'output'));
      await temp.writeAsBytes(bytes, flush: true);
      if (!overwrite && await output.exists()) {
        throw FileSystemException('Output already exists', outputPath);
      }
      await temp.rename(outputPath);
      return outputPath;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static Future<PdfMetadataInfo?> readPdfMetadata(String inputPath) =>
      Isolate.run(() {
        syncfusion.PdfDocument? document;
        try {
          document = syncfusion.PdfDocument(
              inputBytes: File(inputPath).readAsBytesSync());
          final info = document.documentInformation;
          return PdfMetadataInfo(
            title: info.title,
            author: info.author,
            subject: info.subject,
            keywords: info.keywords,
          );
        } catch (_) {
          return null;
        } finally {
          document?.dispose();
        }
      });

  static Future<String?> editPdfMetadata({
    required String inputPath,
    required String outputPath,
    required String title,
    required String author,
    required String subject,
    required String keywords,
    void Function(JobProgress)? onProgress, Future<void> Function()? checkCancelled
  }) => JobQueue().enqueue(_EditMetadataJob(inputPath, outputPath, title, author, subject, keywords), onProgress: onProgress, checkCancelled: checkCancelled);

  static syncfusion.PdfPage addPage(syncfusion.PdfDocument document, Size size,
      {syncfusion.PdfPageRotateAngle rotation =
          syncfusion.PdfPageRotateAngle.rotateAngle0}) {
    // A section owns its settings; changing document-wide settings can resize
    // previously added pages in mixed-size documents.
    final section = document.sections!.add();
    section.pageSettings.orientation = size.width > size.height
        ? syncfusion.PdfPageOrientation.landscape
        : syncfusion.PdfPageOrientation.portrait;
    section.pageSettings.size = size;
    section.pageSettings.margins.all = 0;
    section.pageSettings.rotate = rotation;
    return section.pages.add();
  }

  static void copyPage(
      syncfusion.PdfDocument target, syncfusion.PdfPage source) {
    addPage(target, source.size, rotation: source.rotation)
        .graphics
        .drawPdfTemplate(source.createTemplate(), Offset.zero);
  }

  static Future<String?> mergePdfs(List<String> inputPaths, String outputPath, {void Function(JobProgress)? onProgress, Future<void> Function()? checkCancelled}) =>
      JobQueue().enqueue(_MergePdfsJob(inputPaths, outputPath), onProgress: onProgress, checkCancelled: checkCancelled);

  static Future<String?> rearrangePdf(String inputPath, String outputPath, List<int> pagesToExtract, {void Function(JobProgress)? onProgress, Future<void> Function()? checkCancelled}) =>
      JobQueue().enqueue(_RearrangePdfJob(inputPath, outputPath, pagesToExtract), onProgress: onProgress, checkCancelled: checkCancelled);

  static Future<String?> splitPdf(
          String inputPath, String outputDirPath, List<int> pagesToExtract) =>
      rearrangePdf(
          inputPath,
          p.join(outputDirPath,
              'split_${DateTime.now().microsecondsSinceEpoch}.pdf'),
          pagesToExtract);

  static Future<String?> compressPdf(String inputPath, String outputPath,
      {void Function(JobProgress)? onProgress, Future<void> Function()? checkCancelled,
      int quality = 40,
      int maxThreads = 2,
      Future<PdfDocument> Function(String)? openDocument}) => JobQueue().enqueue(_CompressPdfJob(inputPath, outputPath, quality, maxThreads, openDocument), onProgress: onProgress, checkCancelled: checkCancelled);

  static Future<String?> _compressPdfImpl(String inputPath, String outputPath,
      {int quality = 40,
      int maxThreads = 2,
      Future<PdfDocument> Function(String)? openDocument,
      void Function(JobProgress)? onProgress,
      Future<void> Function()? checkCancelled}) async {
    if (maxThreads < 1 ||
        quality < 1 ||
        quality > 100 ||
        await File(outputPath).exists()) {
      return null;
    }
    PdfDocument? document;
    try {
      document = await (openDocument ?? PdfDocument.openFile)(inputPath);
      final pages = <({Uint8List bytes, double width, double height})>[];
      if (document.pages.isEmpty) return null;
      // Render sequentially (PDFium), then encode a bounded batch in parallel.
      for (var start = 0; start < document.pages.length; start += maxThreads) {
        final batch = <({
          Uint8List pixels,
          int width,
          int height,
          double originalWidth,
          double originalHeight
        })>[];
        final end = (start + maxThreads).clamp(0, document.pages.length);
        if (onProgress != null) onProgress(JobProgress(percentage: start / document.pages.length, stage: "Compressing pages..."));
        if (checkCancelled != null) await checkCancelled();
        for (var index = start; index < end; index++) {
          final page = document.pages[index];
          final scale = [1.0, 1200 / page.width, 1600 / page.height]
              .reduce((a, b) => a < b ? a : b);
          final image = await page.render(
              fullWidth: page.width * scale, fullHeight: page.height * scale);
          if (image == null) throw StateError('Page rendering failed');
          late Uint8List pixels;
          final width = image.width;
          final height = image.height;
          try {
            pixels = Uint8List.fromList(image.pixels);
          } finally {
            image.dispose();
          }
          batch.add((
            pixels: pixels,
            width: width,
            height: height,
            originalWidth: page.width,
            originalHeight: page.height
          ));
        }
        pages.addAll(await Future.wait(batch.map((page) async {
          final bytes = await Isolate.run(() => img.encodeJpg(
              img.Image.fromBytes(
                  width: page.width,
                  height: page.height,
                  bytes: page.pixels.buffer,
                  numChannels: 4,
                  order: img.ChannelOrder.bgra),
              quality: quality));
          return (
            bytes: bytes,
            width: page.originalWidth,
            height: page.originalHeight
          );
        })));
      }
      return await Isolate.run(() async {
        final output = syncfusion.PdfDocument();
        try {
          output.compressionLevel = syncfusion.PdfCompressionLevel.best;
          for (final page in pages) {
            addPage(output, Size(page.width, page.height)).graphics.drawImage(
                syncfusion.PdfBitmap(page.bytes),
                Rect.fromLTWH(0, 0, page.width, page.height));
          }
          return await ToolsService.save(output.saveSync(), outputPath);
        } finally {
          output.dispose();
        }
      });
    } catch (_) {
      return null;
    } finally {
      await document?.dispose();
    }
  }

  static Future<String?> pdfToImages(String inputPath, String outputParent,
      {void Function(JobProgress)? onProgress, Future<void> Function()? checkCancelled,
      Future<PdfDocument> Function(String)? openDocument}) => JobQueue().enqueue(_PdfToImagesJob(inputPath, outputParent, openDocument), onProgress: onProgress, checkCancelled: checkCancelled);

  static Future<String?> _pdfToImagesImpl(String inputPath, String outputParent,
      {Future<PdfDocument> Function(String)? openDocument,
      void Function(JobProgress)? onProgress,
      Future<void> Function()? checkCancelled}) async {
    PdfDocument? document;
    Directory? output;
    try {
      document = await (openDocument ?? PdfDocument.openFile)(inputPath);
      if (document.pages.isEmpty) return null;
      output = await Directory(outputParent).createTemp('Extracted_');
      for (var index = 0; index < document.pages.length; index++) {
        if (onProgress != null) onProgress(JobProgress(percentage: index / document.pages.length, stage: "Extracting pages..."));
        if (checkCancelled != null) await checkCancelled();
        final page = document.pages[index];
        final image =
            await page.render(fullWidth: page.width, fullHeight: page.height);
        if (image == null) throw StateError('Page rendering failed');
        late Uint8List pixels;
        final width = image.width;
        final height = image.height;
        try {
          pixels = Uint8List.fromList(image.pixels);
        } finally {
          image.dispose();
        }
        final outputPath = p.join(output.path, 'page_${index + 1}.jpg');
        // Await each encoder/write: bounded memory and no mutable loop index
        // captured by deferred isolate work.
        await Isolate.run(() async {
          final bitmap = img.Image.fromBytes(
              width: width,
              height: height,
              bytes: pixels.buffer,
              numChannels: 4,
              order: img.ChannelOrder.bgra);
          await File(outputPath)
              .writeAsBytes(img.encodeJpg(bitmap, quality: 90));
        });
      }
      return output.path;
    } catch (_) {
      if (output != null && await output.exists()) {
        await output.delete(recursive: true);
      }
      return null;
    } finally {
      await document?.dispose();
    }
  }

  static Future<String?> imagesToPdf(List<String> imagePaths, String outputPath, {void Function(JobProgress)? onProgress, Future<void> Function()? checkCancelled}) =>
      JobQueue().enqueue(_ImagesToPdfJob(imagePaths, outputPath), onProgress: onProgress, checkCancelled: checkCancelled);
}

class _MergePdfsJob extends Job<String?> {
  final List<String> inputPaths;
  final String outputPath;

  _MergePdfsJob(this.inputPaths, this.outputPath);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled) async {
    final document = syncfusion.PdfDocument();
    final sources = <syncfusion.PdfDocument>[];
    try {
      if (inputPaths.length < 2) return null;
      for (int i = 0; i < inputPaths.length; i++) {
        final path = inputPaths[i];
        if (onProgress != null) onProgress(JobProgress(percentage: i / inputPaths.length, stage: 'Merging PDFs...'));
        if (checkCancelled != null) await checkCancelled();
        final source = syncfusion.PdfDocument(
            inputBytes: File(path).readAsBytesSync());
        sources.add(source);
        for (var j = 0; j < source.pages.count; j++) {
          ToolsService.copyPage(document, source.pages[j]);
        }
      }
      return await ToolsService.save(document.saveSync(), outputPath);
    } catch (_) {
      return null;
    } finally {
      document.dispose();
      for (final source in sources) {
        source.dispose();
      }
    }
  }
}

class _RearrangePdfJob extends Job<String?> {
  final String inputPath;
  final String outputPath;
  final List<int> pagesToExtract;

  _RearrangePdfJob(this.inputPath, this.outputPath, this.pagesToExtract);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled) async {
    syncfusion.PdfDocument? source;
    final document = syncfusion.PdfDocument();
    try {
      source = syncfusion.PdfDocument(
          inputBytes: File(inputPath).readAsBytesSync());
      if (pagesToExtract.isEmpty ||
          pagesToExtract
              .any((page) => page < 1 || page > source!.pages.count)) {
        return null;
      }
      for (int i = 0; i < pagesToExtract.length; i++) {
        final page = pagesToExtract[i];
        if (onProgress != null) onProgress(JobProgress(percentage: i / pagesToExtract.length, stage: 'Rearranging pages...'));
        if (checkCancelled != null) await checkCancelled();
        ToolsService.copyPage(document, source.pages[page - 1]);
      }
      return await ToolsService.save(document.saveSync(), outputPath);
    } catch (_) {
      return null;
    } finally {
      document.dispose();
      source?.dispose();
    }
  }
}


class _ImagesToPdfJob extends Job<String?> {
  final List<String> imagePaths;
  final String outputPath;

  _ImagesToPdfJob(this.imagePaths, this.outputPath);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled) async {
    final document = syncfusion.PdfDocument();
    try {
      if (imagePaths.isEmpty) return null;
      for (int i = 0; i < imagePaths.length; i++) {
        final path = imagePaths[i];
        if (onProgress != null) onProgress(JobProgress(percentage: i / imagePaths.length, stage: 'Converting images...'));
        if (checkCancelled != null) await checkCancelled();

        final bytes = File(path).readAsBytesSync();
        syncfusion.PdfBitmap bitmap;
        try {
          bitmap = syncfusion.PdfBitmap(bytes);
        } catch (_) {
          final decoded = img.decodeImage(bytes);
          if (decoded == null) return null;
          bitmap = syncfusion.PdfBitmap(img.encodePng(decoded));
        }
        final size =
            Size(bitmap.width.toDouble(), bitmap.height.toDouble());
        ToolsService.addPage(document, size).graphics.drawImage(
            bitmap, Rect.fromLTWH(0, 0, size.width, size.height));
      }
      return await ToolsService.save(document.saveSync(), outputPath);
    } catch (_) {
      return null;
    } finally {
      document.dispose();
    }
  }
}

class _CompressPdfJob extends Job<String?> {
  final String inputPath;
  final String outputPath;
  final int quality;
  final int maxThreads;
  final Future<PdfDocument> Function(String)? openDocument;

  _CompressPdfJob(this.inputPath, this.outputPath, this.quality, this.maxThreads, this.openDocument);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled) {
    // A wrapper around the original implementation
    return ToolsService._compressPdfImpl(inputPath, outputPath, quality: quality, maxThreads: maxThreads, openDocument: openDocument, onProgress: onProgress, checkCancelled: checkCancelled);
  }
}

class _PdfToImagesJob extends Job<String?> {
  final String inputPath;
  final String outputParent;
  final Future<PdfDocument> Function(String)? openDocument;

  _PdfToImagesJob(this.inputPath, this.outputParent, this.openDocument);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled) {
    return ToolsService._pdfToImagesImpl(inputPath, outputParent, openDocument: openDocument, onProgress: onProgress, checkCancelled: checkCancelled);
  }
}

class _EditMetadataJob extends Job<String?> {
  final String inputPath;
  final String outputPath;
  final String title;
  final String author;
  final String subject;
  final String keywords;

  _EditMetadataJob(this.inputPath, this.outputPath, this.title, this.author, this.subject, this.keywords);

  @override
  Future<String?> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled) async {
    syncfusion.PdfDocument? document;
    try {
      document = syncfusion.PdfDocument(
          inputBytes: File(inputPath).readAsBytesSync());
      final info = document.documentInformation;
      info.title = title;
      info.author = author;
      info.subject = subject;
      info.keywords = keywords;
      return await ToolsService.save(document.saveSync(), outputPath,
          overwrite:
              p.equals(p.absolute(inputPath), p.absolute(outputPath)));
    } catch (_) {
      return null;
    } finally {
      document?.dispose();
    }
  }
}
