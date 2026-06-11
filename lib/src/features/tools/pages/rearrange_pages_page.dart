import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:pdfrx/pdfrx.dart';

import '../tools_service.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';
import '../../pdf/home/widgets/pdf_thumbnail.dart';

class RearrangePagesPage extends StatefulWidget {
  const RearrangePagesPage({super.key});

  @override
  State<RearrangePagesPage> createState() => _RearrangePagesPageState();
}

class _RearrangePagesPageState extends State<RearrangePagesPage> {
  String? _selectedFile;
  PdfDocument? _document;
  List<int> _pageOrder = []; // 0-based indices of original pages

  @override
  void dispose() {
    _document?.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: false);
    if (paths != null && paths.isNotEmpty) {
      final path = paths.first;
      setState(() {
        _selectedFile = path;
        _pageOrder.clear();
      });
      _loadPdf(path);
    }
  }

  Future<void> _loadPdf(String path) async {
    try {
      final doc = await PdfDocument.openFile(path);
      setState(() {
        _document = doc;
        _pageOrder = List.generate(doc.pages.length, (i) => i);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load PDF.')));
      }
    }
  }

  Future<void> _processPdf() async {
    if (_selectedFile == null || _pageOrder.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(title: 'Processing', message: 'Saving new PDF...', isLoading: true),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    final outputPath = p.join(dir, 'Rearranged_${DateTime.now().millisecondsSinceEpoch}.pdf');

    // pages in pageOrder are 0-based, our rearrangePdf uses 1-based lists
    final pagesToExtract = _pageOrder.map((e) => e + 1).toList();
    final successPath = await ToolsService.rearrangePdf(_selectedFile!, outputPath, pagesToExtract);

    if (!mounted) return;
    Navigator.of(context).pop(); // pop loading

    if (successPath != null) {
      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(title: 'Success', message: 'Saved to:\n$successPath', isLoading: false, outputPath: successPath),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to save PDF.', isLoading: false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Rearrange / Delete Pages')),
      body: Column(
        children: [
          Expanded(
            child: _selectedFile == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(HugeIcons.strokeRoundedLayers01, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No PDF selected yet.\nTap below to choose a file.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : _document == null
                    ? const Center(child: CircularProgressIndicator())
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        itemCount: _pageOrder.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = _pageOrder.removeAt(oldIndex);
                            _pageOrder.insert(newIndex, item);
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
                          final originalIndex = _pageOrder[index];
                          return Container(
                            key: ValueKey(originalIndex),
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
                                  Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.surfaceContainerHighest,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 60,
                                      height: 80,
                                      child: PdfPageView(
                                        document: _document,
                                        pageNumber: originalIndex + 1,
                                        alignment: Alignment.center,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      'Original Page ${originalIndex + 1}',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: Icon(HugeIcons.strokeRoundedDelete01, color: theme.colorScheme.error, size: 22),
                                        onPressed: () => setState(() => _pageOrder.removeAt(index)),
                                        visualDensity: VisualDensity.compact,
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
                      onPressed: _pickFile,
                      child: Text(_selectedFile == null ? 'Select PDF' : 'Change PDF'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _pageOrder.isNotEmpty ? _processPdf : null,
                      child: const Text('Save PDF'),
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
