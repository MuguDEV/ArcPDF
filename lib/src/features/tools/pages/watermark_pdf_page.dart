import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../tools_service.dart';
import '../utils/tools_directory_util.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../../../shared/widgets/glass_app_bar.dart';

class WatermarkPdfPage extends ConsumerStatefulWidget {
  final List<String>? initialFiles;

  const WatermarkPdfPage({super.key, this.initialFiles});

  @override
  ConsumerState<WatermarkPdfPage> createState() => _WatermarkPdfPageState();
}

class _WatermarkPdfPageState extends ConsumerState<WatermarkPdfPage> {
  final List<String> _selectedFiles = [];
  final _textController = TextEditingController(text: 'CONFIDENTIAL');
  Color _selectedColor = Colors.red.withValues(alpha: 0.3);

  final List<Color> _colorOptions = [
    Colors.red.withValues(alpha: 0.3),
    Colors.blue.withValues(alpha: 0.3),
    Colors.grey.withValues(alpha: 0.3),
    Colors.green.withValues(alpha: 0.3),
    Colors.orange.withValues(alpha: 0.3),
    Colors.purple.withValues(alpha: 0.3),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _selectedFiles.addAll(widget.initialFiles!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickFiles();
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: true);
    if (paths != null && paths.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(paths.where((p) => !_selectedFiles.contains(p)));
      });
    } else if (_selectedFiles.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _processFiles() async {
    final watermark = _textController.text;
    if (watermark.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a watermark text')),
      );
      return;
    }

    if (_selectedFiles.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ToolActionDialog(
        title: _selectedFiles.length == 1 ? 'Watermarking PDF' : 'Batch Watermarking PDFs',
        message: 'Stamping pages...',
        isLoading: true,
      ),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    int successCount = 0;
    String? lastSuccessPath;

    for (final path in _selectedFiles) {
      final originalName = p.basenameWithoutExtension(path);
      final outputPath = p.join(dir, '${originalName}_watermarked.pdf');

      final result = await ToolsService.watermarkPdf(path, outputPath, watermark, _selectedColor);
      if (result != null) {
        successCount++;
        lastSuccessPath = result;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (successCount == _selectedFiles.length && _selectedFiles.length == 1) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(
          title: 'Success',
          message: 'PDF watermarked successfully!',
          isLoading: false,
          outputPath: lastSuccessPath,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(
          title: 'Batch Complete',
          message: 'Successfully watermarked $successCount out of ${_selectedFiles.length} files.\nSaved to: $dir',
          isLoading: false,
          outputPath: dir,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: _selectedFiles.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _processFiles,
              icon: const Icon(HugeIcons.strokeRoundedStamp01),
              label: const Text('Apply Watermark'),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          const GlassSliverAppBar(
            title: Text('Watermark PDF'),
          ),
          if (_selectedFiles.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: FilledButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Select PDFs'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'Watermark Text',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'e.g. CONFIDENTIAL',
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHigh,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Stamp Color',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: _colorOptions.map((c) {
                      final isSelected = c == _selectedColor;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedColor = c;
                          });
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 1.0),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? theme.colorScheme.onSurface : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: isSelected ? Icon(Icons.check, color: theme.colorScheme.surface) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Selected Files (${_selectedFiles.length})',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._selectedFiles.map((path) {
                    final filename = p.basename(path);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: theme.colorScheme.surfaceContainerLow,
                      child: ListTile(
                        leading: const Icon(HugeIcons.strokeRoundedFile01),
                        title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _selectedFiles.remove(path);
                            });
                          },
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 80),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
