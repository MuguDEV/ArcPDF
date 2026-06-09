import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io';

import '../tools_service.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';
import '../../pdf/home/widgets/pdf_thumbnail.dart';

class MergePdfsPage extends StatefulWidget {
  const MergePdfsPage({super.key});

  @override
  State<MergePdfsPage> createState() => _MergePdfsPageState();
}

class _MergePdfsPageState extends State<MergePdfsPage> {
  List<String> _selectedFiles = [];

  Future<void> _pickFiles() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: true);
    if (paths != null && paths.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(paths);
      });
    }
  }

  Future<void> _mergeFiles() async {
    if (_selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least 2 PDFs to merge.')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(title: 'Merging PDFs', message: 'Please wait...', isLoading: true),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    final outputPath = p.join(dir, 'Merged_${DateTime.now().millisecondsSinceEpoch}.pdf');

    final successPath = await ToolsService.mergePdfs(_selectedFiles, outputPath);

    if (!mounted) return;
    Navigator.of(context).pop();

    if (successPath != null) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(title: 'Success', message: 'Saved to:\n$successPath', isLoading: false, outputPath: successPath),
      ).then((_) {
        // The dialog already handles navigation, no need to pop the page here unless they just dismissed it.
        // Actually, popping the page here makes it impossible to open the result because it closes the caller too early.
        // If they want to merge again, they can stay on the page.
      });
    } else {
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to merge.', isLoading: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDFs')),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _selectedFiles.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _selectedFiles.removeAt(oldIndex);
                  _selectedFiles.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final path = _selectedFiles[index];
                final file = File(path);
                final sizeBytes = file.existsSync() ? file.lengthSync() : 0;
                final sizeStr = sizeBytes < 1024 * 1024
                    ? '${(sizeBytes / 1024).toStringAsFixed(0)} KB'
                    : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

                return Padding(
                  key: ValueKey(path),
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 44,
                              height: 58,
                              child: PdfThumbnail(path: path, isEncrypted: false, isCorrupted: false),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.basename(path).replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    sizeStr,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(HugeIcons.strokeRoundedDelete01, color: theme.colorScheme.error, size: 20),
                            onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                          ),
                          Icon(Icons.drag_indicator_rounded, color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.05);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickFiles,
                    child: const Text('Add Files'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _selectedFiles.length >= 2 ? _mergeFiles : null,
                    child: const Text('Merge'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
