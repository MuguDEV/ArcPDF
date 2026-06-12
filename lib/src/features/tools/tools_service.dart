import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'dart:typed_data';
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;

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
  static Future<PdfMetadataInfo?> readPdfMetadata(String inputPath) async {
    return await Isolate.run(() async {
      try {
        final file = File(inputPath);
        if (!file.existsSync()) return null;
        final syncfusion.PdfDocument document =
            syncfusion.PdfDocument(inputBytes: file.readAsBytesSync());

        final info = PdfMetadataInfo(
          title: document.documentInformation.title,
          author: document.documentInformation.author,
          subject: document.documentInformation.subject,
          keywords: document.documentInformation.keywords,
        );

        document.dispose();
        return info;
      } catch (e) {
        return null;
      }
    });
  }

  static Future<String?> editPdfMetadata({
    required String inputPath,
    required String outputPath,
    required String title,
    required String author,
    required String subject,
    required String keywords,
  }) async {
    return await Isolate.run(() async {
      syncfusion.PdfDocument? document;
      try {
        final file = File(inputPath);
        if (!file.existsSync()) return null;

        document = syncfusion.PdfDocument(inputBytes: file.readAsBytesSync());

        document.documentInformation.title = title;
        document.documentInformation.author = author;
        document.documentInformation.subject = subject;
        document.documentInformation.keywords = keywords;

        final bytes = document.saveSync();

        final outputFile = File(outputPath);
        await outputFile.writeAsBytes(bytes);

        return outputPath;
      } catch (e) {
        return null;
      } finally {
        document?.dispose();
      }
    });
  }

  static Future<String?> mergePdfs(
      List<String> inputPaths, String outputPath) async {
    return await Isolate.run(() async {
      try {
        final syncfusion.PdfDocument document = syncfusion.PdfDocument();
        for (var path in inputPaths) {
          final file = File(path);
          if (!file.existsSync()) continue;
          final syncfusion.PdfDocument loadedDocument =
              syncfusion.PdfDocument(inputBytes: file.readAsBytesSync());

          for (int i = 0; i < loadedDocument.pages.count; i++) {
            final syncfusion.PdfPage loadedPage = loadedDocument.pages[i];
            // Match the exact size of the loaded page to prevent cropping
            document.pageSettings.size = loadedPage.size;
            document.pageSettings.margins.all = 0;
            document.pageSettings.rotate = loadedPage.rotation;

            final syncfusion.PdfPage newPage = document.pages.add();
            // Draw the loaded page content onto the new page
            newPage.graphics.drawPdfTemplate(loadedPage.createTemplate(), const Offset(0, 0));
          }
          loadedDocument.dispose();
        }
        final bytes = document.saveSync();
        File(outputPath).writeAsBytesSync(bytes);
        document.dispose();
        return outputPath;
      } catch (e) {
        return null;
      }
    });
  }

  static Future<String?> rearrangePdf(String inputPath, String outputPath, List<int> pagesToExtract) async {
    return await Isolate.run(() async {
      try {
        final file = File(inputPath);
        if (!file.existsSync()) return null;
        final syncfusion.PdfDocument loadedDocument =
            syncfusion.PdfDocument(inputBytes: file.readAsBytesSync());
        final syncfusion.PdfDocument newDocument = syncfusion.PdfDocument();

        for (int pageNum in pagesToExtract) {
          int index = pageNum - 1;
          if (index >= 0 && index < loadedDocument.pages.count) {
            final syncfusion.PdfPage loadedPage = loadedDocument.pages[index];

            newDocument.pageSettings.size = loadedPage.size;
            newDocument.pageSettings.margins.all = 0;
            newDocument.pageSettings.rotate = loadedPage.rotation;

            final syncfusion.PdfPage newPage = newDocument.pages.add();
            newPage.graphics.drawPdfTemplate(loadedPage.createTemplate(), const Offset(0, 0));
          }
        }

        if (newDocument.pages.count == 0) {
           loadedDocument.dispose();
           newDocument.dispose();
           return null;
        }

        final bytes = newDocument.saveSync();
        File(outputPath).writeAsBytesSync(bytes);

        loadedDocument.dispose();
        newDocument.dispose();
        return outputPath;
      } catch (e) {
        return null;
      }
    });
  }

  static Future<String?> splitPdf(String inputPath, String outputDirPath,
      List<int> pagesToExtract) async {
    return await Isolate.run(() async {
      try {
        final file = File(inputPath);
        if (!file.existsSync()) return null;
        final syncfusion.PdfDocument loadedDocument =
            syncfusion.PdfDocument(inputBytes: file.readAsBytesSync());
        final syncfusion.PdfDocument newDocument = syncfusion.PdfDocument();

        for (int pageNum in pagesToExtract) {
          int index = pageNum - 1;
          if (index >= 0 && index < loadedDocument.pages.count) {
            final syncfusion.PdfPage loadedPage = loadedDocument.pages[index];

            // Match the exact size of the loaded page to prevent cropping
            newDocument.pageSettings.size = loadedPage.size;
            newDocument.pageSettings.margins.all = 0;
            newDocument.pageSettings.rotate = loadedPage.rotation;

            final syncfusion.PdfPage newPage = newDocument.pages.add();
            // Draw the loaded page content onto the new page
            newPage.graphics.drawPdfTemplate(loadedPage.createTemplate(), const Offset(0, 0));
          }
        }

        if (newDocument.pages.count == 0) {
           loadedDocument.dispose();
           newDocument.dispose();
           return null;
        }

        final bytes = newDocument.saveSync();
        final outputPath =
            '$outputDirPath/split_${DateTime.now().millisecondsSinceEpoch}.pdf';
        File(outputPath).writeAsBytesSync(bytes);

        loadedDocument.dispose();
        newDocument.dispose();
        return outputPath;
      } catch (e) {
        return null;
      }
    });
  }

  static Future<String?> compressPdf(
      String inputPath, String outputPath, {int quality = 40, int maxThreads = 2}) async {
    try {
      final file = File(inputPath);
      if (!file.existsSync()) return null;

      final pdfDocument = await PdfDocument.openFile(inputPath);

      // We will store the resulting JPEG bytes and the original page physical dimensions.
      // Pre-allocate to maintain perfect page order safely.
      List<Map<String, dynamic>?> processedPages = List.filled(pdfDocument.pages.length, null);

      for (int i = 0; i < pdfDocument.pages.length; i += maxThreads) {
        final batchEnd = (i + maxThreads < pdfDocument.pages.length) ? i + maxThreads : pdfDocument.pages.length;

        // We render all pages in the current batch sequentially to avoid native PDFium concurrency limits
        final List<Future<void>> batchFutures = [];

        for (int j = i; j < batchEnd; j++) {
          final page = pdfDocument.pages[j];

          // Render at a moderate resolution to save space but keep legibility.
          double scale = 1.0;
          if (page.width > 1200) {
            scale = 1200 / page.width;
          } else if (page.height > 1600) {
            scale = 1600 / page.height;
          }

          final pdfImage = await page.render(
            fullWidth: page.width * scale,
            fullHeight: page.height * scale,
          );

          if (pdfImage != null) {
            // Copy pixels from native FFI memory to a dart list before sending to isolate
            final Uint8List pixelsCopy = Uint8List.fromList(pdfImage.pixels);
            final int imgW = pdfImage.width;
            final int imgH = pdfImage.height;
            final bool isBgra = pdfImage.format == PixelFormat.bgra8888;
            final double origW = page.width;
            final double origH = page.height;

            // Now it is safe to dispose the native image to free up RAM before spinning up the isolate
            pdfImage.dispose();

            // Enqueue the heavy JPEG encoding work to an isolate
            final isolateFuture = Isolate.run(() {
              final imgObject = img.Image.fromBytes(
                width: imgW,
                height: imgH,
                bytes: pixelsCopy.buffer,
                numChannels: 4,
                order: isBgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
              );
              return img.encodeJpg(imgObject, quality: quality);
            }).then((jpegBytes) {
              // Assign directly to pre-allocated index to guarantee perfect ordering
              processedPages[j] = {
                'jpegBytes': jpegBytes,
                'originalWidth': origW,
                'originalHeight': origH,
              };
            });

            batchFutures.add(isolateFuture);
          }
        }

        // Wait for all isolates in this batch to finish before moving to the next batch
        // to strictly cap memory usage at `maxThreads` simultaneous pages.
        await Future.wait(batchFutures);
      }

      pdfDocument.dispose();

      // 2. Assemble the new PDF in a background isolate
      final result = await Isolate.run(() async {
        try {
          final newPdf = syncfusion.PdfDocument();
          newPdf.compressionLevel = syncfusion.PdfCompressionLevel.best;

          for (final processedPage in processedPages) {
            if (processedPage == null) continue;

            final jpegBytes = processedPage['jpegBytes'] as Uint8List;
            final double originalW = processedPage['originalWidth'];
            final double originalH = processedPage['originalHeight'];

            final syncfusionImage = syncfusion.PdfBitmap(jpegBytes);

            // Use the original physical dimensions, not the rasterized pixel dimensions
            newPdf.pageSettings.size = Size(originalW, originalH);
            newPdf.pageSettings.margins.all = 0;
            final newPage = newPdf.pages.add();

            newPage.graphics.drawImage(
                syncfusionImage,
                Rect.fromLTWH(0, 0, originalW, originalH));
          }

          final bytes = newPdf.saveSync();
          File(outputPath).writeAsBytesSync(bytes);
          newPdf.dispose();
          return outputPath;
        } catch (e) {
          return null;
        }
      });

      return result;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> imagesToPdf(
      List<String> imagePaths, String outputPath) async {
    return await Isolate.run(() async {
      try {
        final syncfusion.PdfDocument document = syncfusion.PdfDocument();
        for (var path in imagePaths) {
          final file = File(path);
          if (!file.existsSync()) continue;

          final bytes = file.readAsBytesSync();
          final syncfusion.PdfBitmap image = syncfusion.PdfBitmap(bytes);

          // Exact image dimensions
          final double imgWidth = image.width.toDouble();
          final double imgHeight = image.height.toDouble();

          // Create page matching exact image size
          document.pageSettings.size = Size(imgWidth, imgHeight);
          document.pageSettings.margins.all = 0;
          final page = document.pages.add();

          // Draw image explicitly to the exact image bounds to prevent any cropping
          page.graphics.drawImage(
              image,
              Rect.fromLTWH(0, 0, imgWidth, imgHeight));
        }

        final bytes = document.saveSync();
        File(outputPath).writeAsBytesSync(bytes);
        document.dispose();
        return outputPath;
      } catch (e) {
        return null;
      }
    });
  }
}
