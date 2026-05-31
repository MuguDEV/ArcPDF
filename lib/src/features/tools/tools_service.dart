import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ToolsService {
  static Future<String?> mergePdfs(
      List<String> inputPaths, String outputPath) async {
    return await Isolate.run(() async {
      try {
        final PdfDocument document = PdfDocument();
        for (var path in inputPaths) {
          final file = File(path);
          if (!file.existsSync()) continue;
          final PdfDocument loadedDocument =
              PdfDocument(inputBytes: file.readAsBytesSync());

          for (int i = 0; i < loadedDocument.pages.count; i++) {
            final PdfPage loadedPage = loadedDocument.pages[i];
            // Match the exact size of the loaded page to prevent cropping
            document.pageSettings.size = loadedPage.size;
            document.pageSettings.margins.all = 0;
            document.pageSettings.rotate = loadedPage.rotation;

            final PdfPage newPage = document.pages.add();
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

  static Future<String?> splitPdf(String inputPath, String outputDirPath,
      int startPage, int endPage) async {
    return await Isolate.run(() async {
      try {
        final file = File(inputPath);
        if (!file.existsSync()) return null;
        final PdfDocument loadedDocument =
            PdfDocument(inputBytes: file.readAsBytesSync());
        final PdfDocument newDocument = PdfDocument();

        // Ensure valid range
        int start = startPage - 1;
        int end = endPage - 1;
        if (start < 0) start = 0;
        if (end >= loadedDocument.pages.count) {
          end = loadedDocument.pages.count - 1;
        }
        if (start > end) return null;

        for (int i = start; i <= end; i++) {
          final PdfPage loadedPage = loadedDocument.pages[i];

          // Match the exact size of the loaded page to prevent cropping
          newDocument.pageSettings.size = loadedPage.size;
          newDocument.pageSettings.margins.all = 0;
          newDocument.pageSettings.rotate = loadedPage.rotation;

          final PdfPage newPage = newDocument.pages.add();
          // Draw the loaded page content onto the new page
          newPage.graphics.drawPdfTemplate(loadedPage.createTemplate(), const Offset(0, 0));
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
      String inputPath, String outputPath, {int quality = 40}) async {
    // For extreme compression, we can rasterize the entire document into compressed JPEGs
    // using pdfrx natively, but since we are in an isolate, pdfrx doesn't work.
    // Instead we will rely on Syncfusion compression Level Best.
    return await Isolate.run(() async {
      try {
        final file = File(inputPath);
        if (!file.existsSync()) return null;

        // Read existing PDF
        final PdfDocument document =
            PdfDocument(inputBytes: file.readAsBytesSync());

        document.compressionLevel = PdfCompressionLevel.best;
        // Removing metadata can save some space
        document.documentInformation.title = '';
        document.documentInformation.author = '';
        document.documentInformation.subject = '';
        document.documentInformation.keywords = '';
        document.documentInformation.creator = '';

        final bytes = document.saveSync();
        File(outputPath).writeAsBytesSync(bytes);
        document.dispose();
        return outputPath;
      } catch (e) {
        return null;
      }
    });
  }

  static Future<String?> imagesToPdf(
      List<String> imagePaths, String outputPath) async {
    return await Isolate.run(() async {
      try {
        final PdfDocument document = PdfDocument();
        for (var path in imagePaths) {
          final file = File(path);
          if (!file.existsSync()) continue;

          final bytes = file.readAsBytesSync();
          final PdfBitmap image = PdfBitmap(bytes);

          // Create page matching image size or standard size
          document.pageSettings.size =
              Size(image.width.toDouble(), image.height.toDouble());
          document.pageSettings.margins.all = 0;
          final page = document.pages.add();

          // Draw image to fit the page
          page.graphics.drawImage(
              image,
              Rect.fromLTWH(0, 0, page.getClientSize().width,
                  page.getClientSize().height));
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
