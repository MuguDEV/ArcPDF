import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path/path.dart' as p;

import '../settings/settings_controller.dart';
import '../settings/haptic_service.dart';
import 'widgets/tool_card.dart';
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildSectionHeader('PDF Utilities', context)
                        .animate()
                        .fadeIn(duration: 300.ms),
                  ),
                ),
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 500,
                    mainAxisExtent: 80,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildListDelegate([
                    ToolCard(
                      title: 'Merge PDFs',
                      subtitle: 'Combine and reorder multiple PDF files',
                      icon: HugeIcons.strokeRoundedLayers01,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const MergePdfsPage()));
                      },
                    )
                        .animate(delay: 50.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05),
                    ToolCard(
                      title: 'Split PDF',
                      subtitle:
                          'Extract pages from a PDF and save as new files',
                      icon: HugeIcons.strokeRoundedScissor01,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const SplitPdfPage()));
                      },
                    )
                        .animate(delay: 100.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05),
                    ToolCard(
                      title: 'Rearrange / Delete Pages',
                      subtitle: 'Change page order or remove pages from a PDF',
                      icon: HugeIcons.strokeRoundedGridView,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const RearrangePagesPage()));
                      },
                    )
                        .animate(delay: 150.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05),
                    ToolCard(
                      title: 'Compress PDF',
                      subtitle: 'Reduce the file size of your PDF document',
                      icon: HugeIcons.strokeRoundedFile01,
                      onTap: () => _handleCompress(context, ref),
                    )
                        .animate(delay: 200.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05),
                    ToolCard(
                      title: 'Metadata Editor',
                      subtitle: 'View and edit document properties',
                      icon: HugeIcons.strokeRoundedInformationCircle,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const MetadataEditorPage()));
                      },
                    )
                        .animate(delay: 250.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05),
                  ]),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 12),
                    child: _buildSectionHeader('Conversion', context)
                        .animate(delay: 200.ms)
                        .fadeIn(duration: 300.ms),
                  ),
                ),
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 500,
                    mainAxisExtent: 80,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildListDelegate([
                    ToolCard(
                      title: 'Images to PDF',
                      subtitle:
                          'Convert, reorder, and combine images into a PDF',
                      icon: HugeIcons.strokeRoundedImage01,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ImagesToPdfPage()));
                      },
                    )
                        .animate(delay: 250.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05),
                    ToolCard(
                      title: 'PDF to Images',
                      subtitle:
                          'Extract and save each page of a PDF as an image',
                      icon: HugeIcons.strokeRoundedImage02,
                      onTap: () {
                        ref.read(hapticServiceProvider).lightImpact();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PdfToImagesPage()));
                      },
                    )
                        .animate(delay: 300.ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.05),
                  ]),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 140),
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
                              HugeIcons.strokeRoundedFolder01,
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
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
                              const SizedBox(width: 8),
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
                    ),
                  );
                });
              }) ??
          false;

      if (!userPicked) return;
      if (!context.mounted) return;

      var successCount = 0;
      final outputs = <String>[];
      await runToolAction(
        context,
        title: paths.length == 1 ? 'Compressing PDF' : 'Batch Compressing',
        successMessage: (output) =>
            'Compressed $successCount out of ${paths.length} files. Saved to: $output',
        outputFiles: () => outputs,
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
                quality: quality, maxThreads: threads);
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
    }
  }

  Widget _buildSectionHeader(String label, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
