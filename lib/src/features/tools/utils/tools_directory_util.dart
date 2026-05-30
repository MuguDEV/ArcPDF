import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:external_path/external_path.dart';

class ToolsDirectoryUtil {
  static Future<String> getDefaultOutputDirectory() async {
    if (Platform.isAndroid) {
      try {
        final docs = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOCUMENTS);
        final arcPdfDir = Directory('$docs/ArcPDF');
        if (!await arcPdfDir.exists()) {
          await arcPdfDir.create(recursive: true);
        }
        return arcPdfDir.path;
      } catch (e) {
        // Fallback below
      }
    }

    // Fallback for non-Android or if external path fails
    final dir = await getApplicationDocumentsDirectory();
    final arcPdfDir = Directory('${dir.path}/ArcPDF');
    if (!await arcPdfDir.exists()) {
      await arcPdfDir.create(recursive: true);
    }
    return arcPdfDir.path;
  }
}
