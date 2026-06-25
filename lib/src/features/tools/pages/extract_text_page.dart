import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../tools_service.dart';
import '../utils/tools_directory_util.dart';
import '../tool_action_dialog.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../../../shared/widgets/glass_app_bar.dart';

class ExtractTextPage extends ConsumerStatefulWidget {
  final String? initialFile;

  const ExtractTextPage({super.key, this.initialFile});

  @override
  ConsumerState<ExtractTextPage> createState() => _ExtractTextPageState();
}

class _ExtractTextPageState extends ConsumerState<ExtractTextPage> {
  String? _selectedFile;
  String? _extractedText;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _selectedFile = widget.initialFile;
      _processExtraction();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickFile();
      });
    }
  }

  Future<void> _pickFile() async {
    final paths = await InAppPdfSelector.show(context, allowMultiple: false);
    if (paths != null && paths.isNotEmpty) {
      setState(() {
        _selectedFile = paths.first;
        _extractedText = null;
      });
      _processExtraction();
    } else if (_selectedFile == null && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _processExtraction() async {
    if (_selectedFile == null) return;

    setState(() {
      _isExtracting = true;
      _extractedText = null;
    });

    final text = await ToolsService.extractText(_selectedFile!);

    if (!mounted) return;

    setState(() {
      _isExtracting = false;
      _extractedText = text;
    });

    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text could be extracted from this PDF. It might be a scanned image.')),
      );
    }
  }

  Future<void> _saveAsTxt() async {
    if (_extractedText == null || _selectedFile == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ToolActionDialog(
        title: 'Saving file',
        message: 'Writing text file...',
        isLoading: true,
      ),
    );

    final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
    final originalName = p.basenameWithoutExtension(_selectedFile!);
    final outputPath = p.join(dir, '${originalName}_extracted.txt');

    try {
      final file = File(outputPath);
      await file.writeAsString(_extractedText!);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      showDialog(
        context: context,
        builder: (context) => ToolActionDialog(
          title: 'Success',
          message: 'Text saved successfully!',
          isLoading: false,
          outputPath: outputPath,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          GlassSliverAppBar(
            title: const Text('Extract Text'),
            actions: [
              if (_extractedText != null && _extractedText!.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Copy to Clipboard',
                  icon: const Icon(HugeIcons.strokeRoundedCopy01),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _extractedText!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Text copied to clipboard!')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Save as .txt',
                  icon: const Icon(HugeIcons.strokeRoundedFloppyDisk),
                  onPressed: _saveAsTxt,
                ),
              ]
            ],
          ),
          if (_selectedFile == null)
            SliverFillRemaining(
              child: Center(
                child: FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.add),
                  label: const Text('Select PDF'),
                ),
              ),
            )
          else if (_isExtracting)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_extractedText != null && _extractedText!.trim().isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: SelectableText(
                    _extractedText!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(HugeIcons.strokeRoundedFile01, size: 48, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      'No Text Found',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This PDF might be a scanned image.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _pickFile,
                      child: const Text('Try Another PDF'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
