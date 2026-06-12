import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:hugeicons/hugeicons.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'dart:ui';

import '../tools_service.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';
import '../../pdf/home/widgets/pdf_thumbnail.dart';

class MergePdfsPage extends StatefulWidget {
  final List<String>? initialFiles;
  const MergePdfsPage({super.key, this.initialFiles});

  @override
  State<MergePdfsPage> createState() => _MergePdfsPageState();
}

class _MergePdfsPageState extends State<MergePdfsPage> {
  final List<String> _selectedFiles = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles != null) {
      _selectedFiles.addAll(widget.initialFiles!);
    }
  }

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
        // Handled internally by dialog actions
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
            child: _selectedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(HugeIcons.strokeRoundedFile02, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No PDFs selected yet.\nTap "Add Files" to begin.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    itemCount: _selectedFiles.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _selectedFiles.removeAt(oldIndex);
                        _selectedFiles.insert(newIndex, item);
                      });
                    },
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (BuildContext context, Widget? child) {
                          final double animValue = Curves.easeInOut.transform(animation.value);
                          final double elevation = lerpDouble(0, 8, animValue)!;
                          return Material(
                            elevation: elevation,
                            color: Colors.transparent,
                            shadowColor: Colors.black26,
                            borderRadius: BorderRadius.circular(24),
                            child: child,
                          );
                        },
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final path = _selectedFiles[index];
                      final file = File(path);
                      final sizeBytes = file.existsSync() ? file.lengthSync() : 0;
                      final sizeStr = sizeBytes < 1024 * 1024
                          ? '${(sizeBytes / 1024).toStringAsFixed(0)} KB'
                          : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

                      return Container(
                        key: ValueKey(path),
                        margin: const EdgeInsets.only(bottom: 12.0),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: 1.0,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: SizedBox(
                                        width: 56,
                                        height: 72,
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
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(HugeIcons.strokeRoundedHardDrive, size: 12, color: theme.colorScheme.onSurfaceVariant),
                                                const SizedBox(width: 4),
                                                Text(
                                                  sizeStr,
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(HugeIcons.strokeRoundedView, color: theme.colorScheme.primary, size: 22),
                                              onPressed: () => OpenFile.open(path),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            IconButton(
                                              icon: Icon(HugeIcons.strokeRoundedDelete01, color: theme.colorScheme.error, size: 22),
                                              onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.grab,
                                            child: Icon(Icons.drag_indicator_rounded, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                          ),
                                        ),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
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
            ),
          )
        ],
      ),
    );
  }
}
