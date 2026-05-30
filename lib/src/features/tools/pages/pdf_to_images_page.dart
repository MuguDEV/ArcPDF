import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';

class PdfToImagesPage extends StatefulWidget {
  const PdfToImagesPage({super.key});

  @override
  State<PdfToImagesPage> createState() => _PdfToImagesPageState();
}

class _PdfToImagesPageState extends State<PdfToImagesPage> {
  String? _selectedFile;

  Future<void> _pickFile() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: false);
    if (paths != null && paths.isNotEmpty) {
      setState(() => _selectedFile = paths.first);
    }
  }

  Future<void> _extractImages() async {
    if (_selectedFile == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(title: 'Extracting Images', message: 'Please wait...', isLoading: true),
    );

    try {
      final document = await PdfDocument.openFile(_selectedFile!);
      final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
      final outputDir = Directory(p.join(dir, 'Extracted_${DateTime.now().millisecondsSinceEpoch}'));
      await outputDir.create(recursive: true);

      for (int i = 1; i <= document.pages.length; i++) {
        final page = document.pages[i - 1];
        final image = await page.render(width: page.width.toInt(), height: page.height.toInt());
        if (image != null) {
          final imgLib = img.Image.fromBytes(width: image.width, height: image.height, bytes: image.pixels.buffer, numChannels: 4);
          final pngBytes = img.encodePng(imgLib);
          final file = File(p.join(outputDir.path, 'page_$i.png'));
          await file.writeAsBytes(pngBytes);
          image.dispose();
        }
      }
      document.dispose();

      if (!mounted) return;
      Navigator.of(context).pop();

      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(title: 'Success', message: 'Saved to:\n${outputDir.path}', isLoading: false, outputPath: outputDir.path),
      ).then((_) => Navigator.of(context).pop());
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to extract images.', isLoading: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF to Images')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedFile != null)
               Text('Selected: ${p.basename(_selectedFile!)}')
            else
               const Text('No file selected.'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _pickFile, child: const Text('Select PDF')),
            const Spacer(),
            FilledButton(
              onPressed: _selectedFile != null ? _extractImages : null,
              child: const Text('Extract Images'),
            ),
          ],
        ),
      ),
    );
  }
}
