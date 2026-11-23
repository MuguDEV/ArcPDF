import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';
import 'dart:io';

import '../tools_service.dart';
import '../utils/run_tool_action.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';
import '../job_queue.dart';
import '../../pdf/home/widgets/pdf_thumbnail.dart';

import '../../pdf/domain/pdf_file_item.dart';

class SplitPdfPage extends StatefulWidget {
  final PdfFileItem? initialFile;
  const SplitPdfPage({super.key, this.initialFile});

  @override
  State<SplitPdfPage> createState() => _SplitPdfPageState();
}

class _SplitPdfPageState extends State<SplitPdfPage> {
  String? _selectedFile;
  final TextEditingController _pagesController = TextEditingController();

  @override
  void dispose() {
    _pagesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _selectedFile = widget.initialFile!.path;
    }
  }

  Future<void> _pickFile() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: false);
    if (!mounted) return;
    if (paths != null && paths.isNotEmpty) {
      setState(() {
        _selectedFile = paths.first;
        _pagesController.clear();
      });
    }
  }

  Future<void> _splitPdf() async {
    final input = _selectedFile;
    if (input == null) return;
    final selection = _pagesController.text;
    final progress =
        ValueNotifier(const JobProgress(percentage: 0, stage: 'Preparing…'));
    VoidCallback? cancel;
    final outputFiles = <String>[];
    await runToolAction(context,
        title: 'Splitting PDF',
        inputPaths: [input],
        progress: progress,
        onCancel: () => cancel?.call(),
        outputFiles: () => outputFiles,
        successMessage: (output) =>
            'Created ${outputFiles.length} PDF ${outputFiles.length == 1 ? 'file' : 'files'} in:\n$output',
        action: () async {
          final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
          final output = await ToolsService.splitPdfSelection(
              input, dir, selection,
              onProgress: (value) => progress.value = value,
              onHandle: (handle) => cancel = handle.cancel);
          if (output != null) {
            outputFiles.addAll(await Directory(output)
                .list(followLinks: false)
                .where((entry) =>
                    entry is File &&
                    p.extension(entry.path).toLowerCase() == '.pdf')
                .map((entry) => entry.path)
                .toList());
            outputFiles.sort();
          }
          return output;
        });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Split PDF')),
      body: Column(
        children: [
          Expanded(
            child: _selectedFile == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(ArcIcons.document,
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow
                                    .withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
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
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${(File(_selectedFile!).statSync().size.clamp(0, 0x7fffffffffffffff) / (1024 * 1024)).toStringAsFixed(1)} MB',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ).animate().fadeIn().slideY(begin: 0.1),
                        const SizedBox(height: 32),
                        Text(
                          'Pages to Extract',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _pagesController,
                          decoration: InputDecoration(
                            hintText: 'e.g. 1, 3-5, 7',
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: const Icon(ArcIcons.merge),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Each comma-separated page or range becomes its own PDF. Example: 1, 3-5, 8 creates three files.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
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
                      onPressed: _selectedFile != null ? _splitPdf : null,
                      child: const Text('Split PDF'),
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
