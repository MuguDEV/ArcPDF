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
  bool _metadataReadFailed = false;
  int _loadGeneration = 0;
  bool _isProcessing = false;

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
    if (!mounted || files.isEmpty || _isProcessing) return;
    final generation = ++_loadGeneration;

    setState(() {
      _selectedFiles = files;
      _isLoadingInfo = true;
      _metadataReadFailed = false;

      _titleController.text = '';
      _authorController.text = '';
      _subjectController.text = '';
      _keywordsController.text = '';
    });

    if (files.length == 1) {
      final info = await ToolsService.readPdfMetadata(files.first.path);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoadingInfo = false;
          _metadataReadFailed = info == null;
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
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoadingInfo = false;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (_selectedFiles.isEmpty || _isProcessing || _isLoadingInfo) return;
    FocusScope.of(context).unfocus();
    ref.read(hapticServiceProvider).mediumImpact();
    setState(() => _isProcessing = true);
    final files = List.of(_selectedFiles);
    final title = _titleController.text.trim();
    final author = _authorController.text.trim();
    final subject = _subjectController.text.trim();
    final keywords = _keywordsController.text.trim();
    try {
      final saveAsCopy = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const _SaveOptionsSheet(),
      );
      if (saveAsCopy == null || !mounted) return;
      final targetDir = saveAsCopy
          ? await ToolsDirectoryUtil.getDefaultOutputDirectory()
          : p.dirname(files.first.path);
      final results = <String>[];
      for (final file in files) {
        var outputPath = file.path;
        if (saveAsCopy) {
          final base = p.basenameWithoutExtension(file.path);
          outputPath = p.join(targetDir, '${base}_meta.pdf');
          var counter = 1;
          while (File(outputPath).existsSync()) {
            outputPath = p.join(targetDir, '${base}_meta_$counter.pdf');
            counter++;
          }
        }
        final result = await ToolsService.editPdfMetadata(
          inputPath: file.path,
          outputPath: outputPath,
          title: title,
          author: author,
          subject: subject,
          keywords: keywords,
        );
        if (result != null) results.add(result);
      }
      if (!mounted) return;
      if (results.isNotEmpty) {
        ref.read(pdfLibraryControllerProvider.notifier).refresh();
      }
      await showDialog<void>(
        context: context,
        builder: (_) => ToolActionDialog(
          title: results.isEmpty
              ? 'Update Failed'
              : results.length == files.length
                  ? 'Metadata Updated!'
                  : 'Partial Update',
          message:
              'Updated properties for ${results.length} out of ${files.length} files.',
          outputFiles: results,
          outputPath: results.isEmpty
              ? null
              : results.length == 1
                  ? results.first
                  : targetDir,
          isLoading: false,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => const ToolActionDialog(
          title: 'Update Failed',
          message: 'Unable to save document properties.',
          isLoading: false,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildTextField(
      String label, TextEditingController controller, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: !_isProcessing,
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
                      if (_isProcessing) return;
                      ref.read(hapticServiceProvider).lightImpact();
                      final paths = await InAppPdfSelector.show(context,
                          allowMultiple: true);
                      if (mounted && paths != null && paths.isNotEmpty) {
                        _handleFilesSelected(paths
                            .map((p) => PdfFileItem.fromFile(File(p)))
                            .toList());
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(HugeIcons.strokeRoundedPdf02,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _selectedFiles.isNotEmpty
                                  ? (_selectedFiles.length == 1
                                      ? p.basename(_selectedFiles.first.path)
                                      : '${_selectedFiles.length} files selected')
                                  : 'Tap to select PDF(s)...',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: _selectedFiles.isNotEmpty
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(HugeIcons.strokeRoundedArrowRight01,
                              color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Text(
                      _selectedFiles.length == 1
                          ? 'Document Properties'
                          : 'Batch Apply Properties',
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
                    else if (_metadataReadFailed)
                      const Text(
                          'Unable to read document properties. Please select a readable PDF before editing.')
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildTextField('Title', _titleController,
                                HugeIcons.strokeRoundedText),
                            _buildTextField('Author', _authorController,
                                HugeIcons.strokeRoundedUser),
                            _buildTextField('Subject', _subjectController,
                                HugeIcons.strokeRoundedBookOpen01),
                            _buildTextField('Keywords', _keywordsController,
                                HugeIcons.strokeRoundedTag01),
                          ],
                        ),
                      ).animate().fadeIn().slideY(begin: 0.1),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: _isProcessing ? null : _handleSave,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(HugeIcons.strokeRoundedTick01),
                        label:
                            Text(_isProcessing ? 'Saving...' : 'Apply Changes'),
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
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Save Options',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
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
                child: Icon(HugeIcons.strokeRoundedFile02,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              title: const Text('Save as New File'),
              subtitle: const Text('Keeps original safe, creates a new file.'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
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
                child: Icon(HugeIcons.strokeRoundedAlert02,
                    color: theme.colorScheme.onErrorContainer),
              ),
              title: const Text('Overwrite Original'),
              subtitle: const Text('Replaces the current file directly.'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
