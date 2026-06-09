import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
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
      builder: (context) => const ToolActionDialog(
          title: 'Extracting Images',
          message: 'Please wait...',
          isLoading: true),
    );

    try {
      final document = await PdfDocument.openFile(_selectedFile!);
      final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
      final outputDir = Directory(
          p.join(dir, 'Extracted_${DateTime.now().millisecondsSinceEpoch}'));
      await outputDir.create(recursive: true);

      final List<Future<void>> writeTasks = [];

      for (int i = 1; i <= document.pages.length; i++) {
        final page = document.pages[i - 1];
        final image = await page.render(
            width: page.width.toInt(), height: page.height.toInt());
        if (image != null) {
          // Offload heavy image encoding and saving to an Isolate
          final isBgra = image.format.name.toLowerCase().contains('bgra');
          final width = image.width;
          final height = image.height;

          // Copy pixel data to avoid FFI constraints and Use-After-Free crashes across Isolates
          final pixelsCopy = image.pixels.buffer.asUint8List().toList(growable: false);

          final futureTask = Isolate.run(() async {
            final imgLib = img.Image.fromBytes(
              width: width,
              height: height,
              bytes: Uint8List.fromList(pixelsCopy).buffer,
              numChannels: 4,
              order: isBgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
            );
            // Use JPEG instead of PNG for much faster encoding and smaller file size
            final jpgBytes = img.encodeJpg(imgLib, quality: 90);
            final file = File(p.join(outputDir.path, 'page_$i.jpg'));
            await file.writeAsBytes(jpgBytes);
          });

          writeTasks.add(futureTask);
          image.dispose();
        }
      }

      // Wait for all background isolate writing tasks to complete
      await Future.wait(writeTasks);

      document.dispose();

      if (!mounted) return;
      Navigator.of(context).pop();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(
            title: 'Success',
            message: 'Saved to:\n${outputDir.path}',
            isLoading: false,
            outputPath: outputDir.path),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(
            title: 'Error',
            message: 'Failed to extract images.',
            isLoading: false),
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
            ElevatedButton(
                onPressed: _pickFile, child: const Text('Select PDF')),
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
