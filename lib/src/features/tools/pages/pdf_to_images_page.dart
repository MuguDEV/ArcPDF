import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';

import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';
import '../../pdf/home/widgets/pdf_thumbnail.dart';

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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PDF to Images')),
      body: Column(
        children: [
          Expanded(
            child: _selectedFile == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(HugeIcons.strokeRoundedImage02, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No PDF selected yet.\nTap "Select PDF" to begin.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  width: 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: SizedBox(
                                      width: 120,
                                      height: 160,
                                      child: PdfThumbnail(path: _selectedFile!, isEncrypted: false, isCorrupted: false),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    p.basename(_selectedFile!),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${(File(_selectedFile!).lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ).animate().fadeIn().slideY(begin: 0.1),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(HugeIcons.strokeRoundedInformationCircle, color: theme.colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'This will extract all pages as high-quality JPG images into a new folder.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickFile,
                      child: Text(_selectedFile == null ? 'Select PDF' : 'Change PDF'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedFile != null ? _extractImages : null,
                      child: const Text('Extract Images'),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
