import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../tools_service.dart';
import '../tool_action_dialog.dart';
import '../utils/tools_directory_util.dart';

class ImagesToPdfPage extends StatefulWidget {
  const ImagesToPdfPage({super.key});

  @override
  State<ImagesToPdfPage> createState() => _ImagesToPdfPageState();
}

class _ImagesToPdfPageState extends State<ImagesToPdfPage> {
  final List<String> _selectedFiles = [];

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.paths.whereType<String>());
      });
    }
  }

  Future<void> _convert() async {
    if (_selectedFiles.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(title: 'Converting', message: 'Please wait...', isLoading: true),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    final outputPath = p.join(dir, 'ImagesToPDF_${DateTime.now().millisecondsSinceEpoch}.pdf');

    final successPath = await ToolsService.imagesToPdf(_selectedFiles, outputPath);

    if (!mounted) return;
    Navigator.of(context).pop();

    if (successPath != null) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(title: 'Success', message: 'Saved to:\n$successPath', isLoading: false, outputPath: successPath),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to convert.', isLoading: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Images to PDF')),
      body: Column(
        children: [
          Expanded(
            child: _selectedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(HugeIcons.strokeRoundedImage01, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No images selected yet.\nTap "Add Images" to begin.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
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

                      return Padding(
                        key: ValueKey(path),
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
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
                                      child: Image.file(file, width: 56, height: 72, fit: BoxFit.cover),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.basename(path),
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
                                        IconButton(
                                          icon: Icon(HugeIcons.strokeRoundedDelete01, color: theme.colorScheme.error, size: 22),
                                          onPressed: () => setState(() => _selectedFiles.removeAt(index)),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(height: 4),
                                        Icon(Icons.drag_indicator_rounded, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.05);
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
                      child: const Text('Add Images'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedFiles.isNotEmpty ? _convert : null,
                      child: const Text('Convert to PDF'),
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
