import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../../settings/haptic_service.dart';
import '../../../shared/widgets/glass_app_bar.dart';
import '../../pdf/domain/pdf_file_item.dart';
import '../../pdf/application/pdf_library_controller.dart';
import '../utils/tools_directory_util.dart';
import '../widgets/in_app_pdf_selector.dart';
import '../tools_service.dart';
import '../tool_action_dialog.dart';

class MetadataEditorPage extends ConsumerStatefulWidget {
  final PdfFileItem? initialFile;
  const MetadataEditorPage({super.key, this.initialFile});

  @override
  ConsumerState<MetadataEditorPage> createState() => _MetadataEditorPageState();
}

class _MetadataEditorPageState extends ConsumerState<MetadataEditorPage> {
  List<PdfFileItem> _selectedFiles = [];
  bool _isLoadingInfo = false;
  bool _isProcessing = false;
  PdfMetadataInfo? _originalInfo;

  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _subjectController = TextEditingController();
  final _keywordsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _handleFilesSelected([widget.initialFile!]);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _subjectController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _handleFilesSelected(List<PdfFileItem> files) async {
    if (files.isEmpty) return;

    setState(() {
      _selectedFiles = files;
      _isLoadingInfo = true;
      _originalInfo = null;

      _titleController.text = '';
      _authorController.text = '';
      _subjectController.text = '';
      _keywordsController.text = '';
    });

    if (files.length == 1) {
      final info = await ToolsService.readPdfMetadata(files.first.path);
      if (mounted) {
        setState(() {
          _isLoadingInfo = false;
          _originalInfo = info;
          if (info != null) {
            _titleController.text = info.title;
            _authorController.text = info.author;
            _subjectController.text = info.subject;
            _keywordsController.text = info.keywords;
          }
        });
      }
    } else {
      // For batch processing, we don't prefill metadata since files likely differ.
      if (mounted) {
        setState(() {
          _isLoadingInfo = false;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (_selectedFiles.isEmpty) return;

    // Unfocus keyboard
    FocusScope.of(context).unfocus();
    ref.read(hapticServiceProvider).mediumImpact();

    // Ask user: Overwrite or Save as Copy
    final saveAsCopy = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _SaveOptionsSheet(),
    );

    if (saveAsCopy == null || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      int successCount = 0;
      final targetDir = await ToolsDirectoryUtil.getDefaultOutputDirectory();

      for (final file in _selectedFiles) {
        final inputPath = file.path;
        String outputPath;

        if (saveAsCopy) {
          final baseName = p.basenameWithoutExtension(inputPath);
          outputPath = p.join(targetDir, '${baseName}_meta.pdf');

          int counter = 1;
          while (File(outputPath).existsSync()) {
            outputPath = p.join(targetDir, '${baseName}_meta_$counter.pdf');
            counter++;
          }
        } else {
          // Overwrite: Save to a temp file first, then move
          final tempDir = Directory.systemTemp;
          outputPath = p.join(tempDir.path, 'meta_temp_${DateTime.now().millisecondsSinceEpoch}_${file.name}.pdf');
        }

        final resultPath = await ToolsService.editPdfMetadata(
          inputPath: inputPath,
          outputPath: outputPath,
          title: _titleController.text.trim(),
          author: _authorController.text.trim(),
          subject: _subjectController.text.trim(),
          keywords: _keywordsController.text.trim(),
        );

        if (resultPath != null) {
          if (!saveAsCopy) {
             final originalFile = File(inputPath);
             final tempFile = File(resultPath);
             if (await tempFile.exists()) {
                await tempFile.copy(inputPath);
                await tempFile.delete();
             }
          }
          successCount++;
        }
      }

      // Refresh library to show changes
      ref.read(pdfLibraryControllerProvider.notifier).refresh();

      if (mounted) {
         showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => ToolActionDialog(
            title: _selectedFiles.length == 1 ? 'Metadata Updated!' : 'Batch Update Complete!',
            message: _selectedFiles.length == 1
                ? 'The document properties have been successfully updated.'
                : 'Successfully updated properties for $successCount out of ${_selectedFiles.length} files.',
            outputPath: _selectedFiles.length == 1 ? (saveAsCopy ? p.join(targetDir, '${p.basenameWithoutExtension(_selectedFiles.first.path)}_meta.pdf') : _selectedFiles.first.path) : targetDir,
            isLoading: false,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerLowest,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          const GlassSliverAppBar(
            title: Text('Metadata Editor'),
            actions: [],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Select PDF',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      ref.read(hapticServiceProvider).lightImpact();
                      final paths = await InAppPdfSelector.show(context, allowMultiple: true);
                      if (paths != null && paths.isNotEmpty) {
                        _handleFilesSelected(paths.map((p) => PdfFileItem.fromFile(File(p))).toList());
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(HugeIcons.strokeRoundedPdf02, color: theme.colorScheme.primary),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _selectedFiles.isNotEmpty
                                  ? (_selectedFiles.length == 1 ? p.basename(_selectedFiles.first.path) : '${_selectedFiles.length} files selected')
                                  : 'Tap to select PDF(s)...',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: _selectedFiles.isNotEmpty ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(HugeIcons.strokeRoundedArrowRight01, color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),

                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Text(
                      _selectedFiles.length == 1 ? 'Document Properties' : 'Batch Apply Properties',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ).animate().fadeIn().slideY(begin: 0.1),
                    const SizedBox(height: 16),

                    if (_isLoadingInfo)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildTextField('Title', _titleController, HugeIcons.strokeRoundedText),
                            _buildTextField('Author', _authorController, HugeIcons.strokeRoundedUser),
                            _buildTextField('Subject', _subjectController, HugeIcons.strokeRoundedBookOpen01),
                            _buildTextField('Keywords', _keywordsController, HugeIcons.strokeRoundedTag01),
                          ],
                        ),
                      ).animate().fadeIn().slideY(begin: 0.1),

                      const SizedBox(height: 32),

                      FilledButton.icon(
                        onPressed: _isProcessing ? null : _handleSave,
                        icon: _isProcessing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(HugeIcons.strokeRoundedTick01),
                        label: Text(_isProcessing ? 'Saving...' : 'Apply Changes'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ).animate().fadeIn(delay: 100.ms),
                    ],
                  ],
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveOptionsSheet extends StatelessWidget {
  const _SaveOptionsSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Save Options',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'How would you like to save the updated metadata?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ListTile(
              onTap: () => Navigator.pop(context, true), // saveAsCopy = true
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(HugeIcons.strokeRoundedFile02, color: theme.colorScheme.onPrimaryContainer),
              ),
              title: const Text('Save as New File'),
              subtitle: const Text('Keeps original safe, creates a new file.'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            const SizedBox(height: 8),
            ListTile(
              onTap: () => Navigator.pop(context, false), // saveAsCopy = false
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(HugeIcons.strokeRoundedAlert02, color: theme.colorScheme.onErrorContainer),
              ),
              title: const Text('Overwrite Original'),
              subtitle: const Text('Replaces the current file directly.'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
