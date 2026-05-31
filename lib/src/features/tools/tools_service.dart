import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'dart:typed_data';
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;

class ToolsService {
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

  static Future<String?> splitPdf(String inputPath, String outputDirPath,
      int startPage, int endPage) async {
    return await Isolate.run(() async {
      try {
        final file = File(inputPath);
        if (!file.existsSync()) return null;
        final syncfusion.PdfDocument loadedDocument =
            syncfusion.PdfDocument(inputBytes: file.readAsBytesSync());
        final syncfusion.PdfDocument newDocument = syncfusion.PdfDocument();

        // Ensure valid range
        int start = startPage - 1;
        int end = endPage - 1;
        if (start < 0) start = 0;
        if (end >= loadedDocument.pages.count) {
          end = loadedDocument.pages.count - 1;
        }
        if (start > end) return null;

        for (int i = start; i <= end; i++) {
          final syncfusion.PdfPage loadedPage = loadedDocument.pages[i];

          // Match the exact size of the loaded page to prevent cropping
          newDocument.pageSettings.size = loadedPage.size;
          newDocument.pageSettings.margins.all = 0;
          newDocument.pageSettings.rotate = loadedPage.rotation;

          final syncfusion.PdfPage newPage = newDocument.pages.add();
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
    try {
      final file = File(inputPath);
      if (!file.existsSync()) return null;

      final pdfDocument = await PdfDocument.openFile(inputPath);

      // We will store the resulting JPEG bytes and the original page physical dimensions.
      List<Map<String, dynamic>> processedPages = [];

      for (int i = 0; i < pdfDocument.pages.length; i++) {
        final page = pdfDocument.pages[i];

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
          // Send pixels to an isolate to encode immediately.
          // This prevents holding hundreds of MBs of raw RGBA in memory for the whole document.
          // Note: we must copy the pixels from native FFI memory to a dart list before sending to isolate
          final Uint8List pixelsCopy = Uint8List.fromList(pdfImage.pixels);
          final int imgW = pdfImage.width;
          final int imgH = pdfImage.height;
          final bool isBgra = pdfImage.format == PixelFormat.bgra8888;

          // Now it is safe to dispose the native image
          pdfImage.dispose();

          final jpegBytes = await Isolate.run(() {
            final imgObject = img.Image.fromBytes(
              width: imgW,
              height: imgH,
              bytes: pixelsCopy.buffer,
              numChannels: 4,
              order: isBgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
            );
            return img.encodeJpg(imgObject, quality: quality);
          });

          processedPages.add({
            'jpegBytes': jpegBytes,
            'originalWidth': page.width,
            'originalHeight': page.height,
          });
        }
      }

      pdfDocument.dispose();

      // 2. Assemble the new PDF in a background isolate
      final result = await Isolate.run(() async {
        try {
          final newPdf = syncfusion.PdfDocument();
          newPdf.compressionLevel = syncfusion.PdfCompressionLevel.best;

          for (final processedPage in processedPages) {
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
