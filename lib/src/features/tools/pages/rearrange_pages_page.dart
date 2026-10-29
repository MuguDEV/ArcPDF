import 'dart:ui';
import 'package:flutter/material.dart';
import '../../pdf/application/pdf_error_handler.dart';
import 'package:path/path.dart' as p;
import 'package:hugeicons/hugeicons.dart';
import 'package:pdfrx/pdfrx.dart';

import '../tools_service.dart';
import '../utils/run_tool_action.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../utils/tools_directory_util.dart';

import '../../pdf/domain/pdf_file_item.dart';

class RearrangePagesPage extends StatefulWidget {
  final PdfFileItem? initialFile;
  const RearrangePagesPage({super.key, this.initialFile, this.openDocument});

  final Future<PdfDocument> Function(String)? openDocument;

  @override
  State<RearrangePagesPage> createState() => _RearrangePagesPageState();
}

class _RearrangePagesPageState extends State<RearrangePagesPage> {
  String? _selectedFile;
  PdfDocument? _document;
  List<int> _pageOrder = []; // 0-based indices of original pages
  int _loadGeneration = 0;

  @override
  void dispose() {
    _document?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _loadPdf(widget.initialFile!.path);
    }
  }

  Future<void> _pickFile() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: false);
    if (!mounted) return;
    if (paths != null && paths.isNotEmpty) {
      _loadPdf(paths.first);
    }
  }

  Future<void> _loadPdf(String path) async {
    final generation = ++_loadGeneration;
    final previous = _document;
    setState(() {
      _selectedFile = path;
      _document = null;
      _pageOrder = [];
    });
    await previous?.dispose();
    try {
      final doc = await (widget.openDocument ?? PdfDocument.openFile)(path);
      if (!mounted || generation != _loadGeneration) {
        await doc.dispose();
        return;
      }
      setState(() {
        _document = doc;
        _pageOrder = List.generate(doc.pages.length, (i) => i);
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _selectedFile = null);
        PdfErrorHandler.show(context, e, contextMessage: 'Failed to load PDF.');
      }
    }
  }

  Future<void> _processPdf() async {
    if (_selectedFile == null || _pageOrder.isEmpty) return;
    await runToolAction(context, title: 'Saving PDF', action: () async {
      final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
      return ToolsService.rearrangePdf(
          _selectedFile!,
          p.join(
              dir, 'Rearranged_${DateTime.now().microsecondsSinceEpoch}.pdf'),
          _pageOrder.map((page) => page + 1).toList());
    });
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
                        Icon(HugeIcons.strokeRoundedLayers01,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No PDF selected yet.\nTap below to choose a file.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : _document == null
                    ? const Center(child: CircularProgressIndicator())
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 16),
                        itemCount: _pageOrder.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            final item = _pageOrder.removeAt(oldIndex);
                            _pageOrder.insert(newIndex, item);
                          });
                        },
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (BuildContext context, Widget? child) {
                              final double animValue =
                                  Curves.easeInOut.transform(animation.value);
                              final double elevation =
                                  lerpDouble(0, 8, animValue)!;
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
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
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
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: theme
                                              .colorScheme.onSurfaceVariant),
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
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                            HugeIcons.strokeRoundedDelete01,
                                            color: theme.colorScheme.error,
                                            size: 22),
                                        onPressed: () => setState(
                                            () => _pageOrder.removeAt(index)),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      const SizedBox(height: 4),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.grab,
                                          child: Icon(
                                              Icons.drag_indicator_rounded,
                                              color: theme
                                                  .colorScheme.onSurfaceVariant
                                                  .withValues(alpha: 0.5)),
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
                      child: Text(
                          _selectedFile == null ? 'Select PDF' : 'Change PDF'),
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
