import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../settings/settings_controller.dart';
import '../settings/haptic_service.dart';
import 'widgets/tool_card.dart';
import 'job_queue.dart';
import 'tools_service.dart';
import 'utils/run_tool_action.dart';
import 'pages/merge_pdfs_page.dart';
import 'pages/split_pdf_page.dart';
import 'pages/rearrange_pages_page.dart';
import 'pages/images_to_pdf_page.dart';
import 'pages/pdf_to_images_page.dart';
import 'pages/metadata_editor_page.dart';
import 'widgets/in_app_pdf_selector.dart';
import 'utils/tools_directory_util.dart';
import '../../shared/widgets/glass_app_bar.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          const GlassSliverAppBar(
            title: Text('Tools', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildSectionHeader('PDF utilities', context),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ToolCollection(children: [
                    ToolCard(
                      title: 'Merge PDFs',
                      subtitle: 'Combine multiple files',
                      icon: ArcIcons.merge,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const MergePdfsPage()));
                      },
                    ),
                    ToolCard(
                      title: 'Split PDF',
                      subtitle: 'Save selected pages',
                      icon: ArcIcons.split,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const SplitPdfPage()));
                      },
                    ),
                    ToolCard(
                      title: 'Organize pages',
                      subtitle: 'Reorder or remove pages',
                      icon: ArcIcons.grid,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const RearrangePagesPage()));
                      },
                    ),
                    ToolCard(
                      title: 'Compress PDF',
                      subtitle: 'Reduce document size',
                      icon: ArcIcons.compress,
                      onTap: () => _handleCompress(context, ref),
                    ),
                    ToolCard(
                      title: 'Edit metadata',
                      horizontal: true,
                      subtitle: 'Update title and author',
                      icon: ArcIcons.info,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const MetadataEditorPage()));
                      },
                    ),
                  ]),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 12),
                    child: _buildSectionHeader('Conversion', context),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ToolCollection(children: [
                    ToolCard(
                      title: 'Images to PDF',
                      subtitle: 'Turn photos into a document',
                      icon: ArcIcons.image,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ImagesToPdfPage()));
                      },
                    ),
                    ToolCard(
                      title: 'PDF to Images',
                      subtitle: 'Save pages as images',
                      icon: ArcIcons.images,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PdfToImagesPage()));
                      },
                    ),
                  ]),
                ),
                const SliverSafeArea(
                  minimum: EdgeInsets.only(bottom: 24),
                  sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCompress(BuildContext context, WidgetRef ref) async {
    ref.read(hapticServiceProvider).lightImpact();
    final threads = ref.read(settingsControllerProvider).compressionThreads;
    final paths = await InAppPdfSelector.show(context, allowMultiple: true);

    if (paths != null && paths.isNotEmpty) {
      if (!context.mounted) return;
      final inputBytes = await _totalBytes(paths);
      if (!context.mounted) return;
      // Let user pick compression level
      int quality = 40; // Default
      bool userPicked = await showDialog<bool>(
              context: context,
              builder: (context) {
                int tempQuality = quality;
                final theme = Theme.of(context);
                return StatefulBuilder(builder: (context, setState) {
                  return Dialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    child: SingleChildScrollView(
                        child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              ArcIcons.compress,
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            paths.length == 1
                                ? 'Compress PDF'
                                : 'Batch Compress ${paths.length} PDFs',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Select the image quality (lower reduces image size). This rasterizes every page: searchable text, links, and forms are not preserved, and the file may become larger. The original is kept.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${paths.length} ${paths.length == 1 ? 'file' : 'files'} · ${_formatBytes(inputBytes)} input',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'The exact output size is measured after compression.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Quality: $tempQuality%',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Slider(
                            value: tempQuality.toDouble(),
                            min: 10,
                            max: 90,
                            divisions: 8,
                            onChanged: (val) {
                              setState(() {
                                tempQuality = val.toInt();
                              });
                            },
                          ),
                          const SizedBox(height: 24),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            overflowAlignment: OverflowBarAlignment.end,
                            spacing: 8,
                            overflowSpacing: 8,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: () {
                                  quality = tempQuality;
                                  Navigator.of(context).pop(true);
                                },
                                child: const Text('Compress'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )),
                  );
                });
              }) ??
          false;

      if (!userPicked) return;
      if (!context.mounted) return;

      var successCount = 0;
      final outputs = <String>[];
      final progress =
          ValueNotifier(const JobProgress(percentage: 0, stage: 'Preparing…'));
      VoidCallback? cancel;
      await runToolAction(
        context,
        title: paths.length == 1 ? 'Compressing PDF' : 'Batch Compressing',
        inputPaths: paths,
        resultKind: ToolResultKind.compression,
        successMessage: (output) =>
            'Compressed $successCount out of ${paths.length} files. Saved to: $output',
        outputFiles: () => outputs,
        progress: progress,
        onCancel: () => cancel?.call(),
        action: () async {
          final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
          String? lastOutput;
          // Avoid multiplying each document's native rendering memory in batches.
          for (var index = 0; index < paths.length; index++) {
            final path = paths[index];
            final name = p.basenameWithoutExtension(path);
            final output = p.join(dir,
                '${name}_compressed_${DateTime.now().microsecondsSinceEpoch}_$index.pdf');
            final result = await ToolsService.compressPdf(path, output,
                quality: quality,
                maxThreads: threads,
                onHandle: (handle) => cancel = handle.cancel,
                onProgress: (value) {
                  final overall = (index + value.percentage) / paths.length;
                  progress.value = JobProgress(
                    percentage: overall.clamp(0.0, 1.0),
                    stage: paths.length == 1
                        ? value.stage
                        : '${value.stage} · File ${index + 1} of ${paths.length}',
                  );
                });
            if (result != null) {
              successCount++;
              outputs.add(result);
              lastOutput = result;
            }
          }
          return successCount == 0
              ? null
              : successCount == 1
                  ? lastOutput
                  : dir;
        },
      );
      progress.dispose();
    }
  }

  Future<int> _totalBytes(List<String> paths) async {
    var total = 0;
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) total += await file.length();
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildSectionHeader(String label, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
