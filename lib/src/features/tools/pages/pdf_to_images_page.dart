import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../utils/run_tool_action.dart';
import '../tools_service.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';
import '../../pdf/home/widgets/pdf_thumbnail.dart';
import '../job_queue.dart';

class PdfToImagesPage extends StatefulWidget {
  const PdfToImagesPage({super.key});

  @override
  State<PdfToImagesPage> createState() => _PdfToImagesPageState();
}

class _PdfToImagesPageState extends State<PdfToImagesPage> {
  String? _selectedFile;
  int _dpi = 144;
  PdfImageFormat _format = PdfImageFormat.jpeg;
  int _quality = 90;

  Future<void> _pickFile() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: false);
    if (!mounted) return;
    if (paths != null && paths.isNotEmpty) {
      setState(() => _selectedFile = paths.first);
    }
  }

  Future<void> _extractImages() async {
    final input = _selectedFile;
    if (input == null) return;
    final progress =
        ValueNotifier(const JobProgress(percentage: 0, stage: 'Preparing…'));
    VoidCallback? cancel;
    await runToolAction(context,
        title: 'Extracting Images',
        progress: progress,
        onCancel: () => cancel?.call(),
        action: () async {
          final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
          return ToolsService.pdfToImages(input, dir,
              dpi: _dpi,
              format: _format,
              quality: _quality,
              onProgress: (value) => progress.value = value,
              onHandle: (handle) => cancel = handle.cancel);
        });
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
                        Icon(ArcIcons.images,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No PDF selected yet.\nTap "Select PDF" to begin.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
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
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 120,
                                  height: 160,
                                  child: PdfThumbnail(
                                      path: _selectedFile!,
                                      isEncrypted: false,
                                      isCorrupted: false),
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
                                '${(File(_selectedFile!).statSync().size.clamp(0, 0x7fffffffffffffff) / (1024 * 1024)).toStringAsFixed(1)} MB',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Image format', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<PdfImageFormat>(
                          segments: const [
                            ButtonSegment(
                                value: PdfImageFormat.jpeg,
                                label: Text('JPEG')),
                            ButtonSegment(
                                value: PdfImageFormat.png, label: Text('PNG')),
                          ],
                          selected: {_format},
                          onSelectionChanged: (value) =>
                              setState(() => _format = value.first),
                        ),
                        const SizedBox(height: 20),
                        Text('Resolution', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _dpi,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(ArcIcons.image),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 72, child: Text('72 DPI · Small')),
                            DropdownMenuItem(
                                value: 144,
                                child: Text('144 DPI · Recommended')),
                            DropdownMenuItem(
                                value: 216, child: Text('216 DPI · Detailed')),
                            DropdownMenuItem(
                                value: 300, child: Text('300 DPI · Print')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _dpi = value);
                          },
                        ),
                        if (_format == PdfImageFormat.jpeg) ...[
                          const SizedBox(height: 20),
                          Text('JPEG quality · $_quality%',
                              style: theme.textTheme.titleSmall),
                          Slider(
                            value: _quality.toDouble(),
                            min: 50,
                            max: 100,
                            divisions: 10,
                            label: '$_quality%',
                            onChanged: (value) =>
                                setState(() => _quality = value.round()),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(ArcIcons.info,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _format == PdfImageFormat.png
                                      ? 'PNG preserves transparency and sharp graphics but uses more storage.'
                                      : 'JPEG is smaller and works well for scanned or photographic pages.',
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
                      child: Text(
                          _selectedFile == null ? 'Select PDF' : 'Change PDF'),
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
