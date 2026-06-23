import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path/path.dart' as p;

import '../settings/settings_controller.dart';
import '../settings/haptic_service.dart';
import 'widgets/tool_card.dart';
import 'tools_service.dart';
import 'tool_action_dialog.dart';
import 'pages/merge_pdfs_page.dart';
import 'pages/split_pdf_page.dart';
import 'pages/rearrange_pages_page.dart';
import 'pages/images_to_pdf_page.dart';
import 'pages/pdf_to_images_page.dart';
import 'pages/metadata_editor_page.dart';
import 'widgets/in_app_pdf_selector.dart';
import 'utils/tools_directory_util.dart';
import '../../shared/widgets/glass_app_bar.dart';
import '../../shared/widgets/dynamic_island_notification.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          const GlassSliverAppBar(
            title: Text('Tools', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 20, top: 24, bottom: 12),
              child: _buildSectionHeader('PDF Utilities', context).animate().fadeIn(duration: 300.ms),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                ToolCard(
                  title: 'Merge PDFs',
                  subtitle: 'Combine and reorder files',
                  icon: HugeIcons.strokeRoundedLayers01,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MergePdfsPage()));
                  },
                ).animate(delay: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'Split PDF',
                  subtitle: 'Extract pages as new files',
                  icon: HugeIcons.strokeRoundedScissor01,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SplitPdfPage()));
                  },
                ).animate(delay: 100.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'Organize Pages',
                  subtitle: 'Reorder or delete pages',
                  icon: HugeIcons.strokeRoundedGridView,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RearrangePagesPage()));
                  },
                ).animate(delay: 150.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'Compress PDF',
                  subtitle: 'Reduce the file size',
                  icon: HugeIcons.strokeRoundedFile01,
                  onTap: () => _handleCompress(context, ref),
                ).animate(delay: 200.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'Metadata Editor',
                  subtitle: 'Edit document properties',
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MetadataEditorPage()));
                  },
                ).animate(delay: 250.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 20, top: 32, bottom: 12),
              child: _buildSectionHeader('Conversion', context).animate(delay: 200.ms).fadeIn(duration: 300.ms),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                ToolCard(
                  title: 'Word to PDF',
                  subtitle: 'Convert .docx to PDF',
                  icon: HugeIcons.strokeRoundedDocumentAttachment,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    DynamicIslandNotification.show(context, 'Coming Soon: Offline Word to PDF conversion!', icon: HugeIcons.strokeRoundedTime01);
                  },
                ).animate(delay: 250.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'PDF to Word',
                  subtitle: 'Convert PDF to .docx',
                  icon: HugeIcons.strokeRoundedFile02,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    DynamicIslandNotification.show(context, 'Coming Soon: ML-powered PDF to Word extraction!', icon: HugeIcons.strokeRoundedTime01);
                  },
                ).animate(delay: 300.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'Images to PDF',
                  subtitle: 'Combine images into a PDF',
                  icon: HugeIcons.strokeRoundedImage01,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImagesToPdfPage()));
                  },
                ).animate(delay: 350.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'PDF to Images',
                  subtitle: 'Save pages as images',
                  icon: HugeIcons.strokeRoundedImage02,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PdfToImagesPage()));
                  },
                ).animate(delay: 400.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'HTML to PDF',
                  subtitle: 'Render webpages into PDF',
                  icon: HugeIcons.strokeRoundedGlobe02,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    DynamicIslandNotification.show(context, 'Coming Soon: Offline HTML rendering engine!', icon: HugeIcons.strokeRoundedTime01);
                  },
                ).animate(delay: 450.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                ToolCard(
                  title: 'Watermark PDF',
                  subtitle: 'Add secure text or images',
                  icon: HugeIcons.strokeRoundedStamp01,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    DynamicIslandNotification.show(context, 'Coming Soon: Batch watermarking tool!', icon: HugeIcons.strokeRoundedTime01);
                  },
                ).animate(delay: 500.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
              ],
            ),
          ),
          const SliverSafeArea(
            minimum: EdgeInsets.only(bottom: 140),
            sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCompress(BuildContext context, WidgetRef ref) async {
    ref.read(hapticServiceProvider).lightImpact();
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
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                        paths.length == 1 ? 'Compress PDF' : 'Batch Compress ${paths.length} PDFs',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select the image quality for compression (lower is smaller file size but worse quality).',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Quality: $tempQuality%',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            }
          );
        }
      ) ?? false;

      if (!userPicked) return;
      if (!context.mounted) return;

      // Single file scenario
      if (paths.length == 1) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const ToolActionDialog(title: 'Compressing PDF', message: 'Applying compression settings...', isLoading: true),
        );

        final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
        final outputPath = p.join(dir, 'Compressed_${DateTime.now().millisecondsSinceEpoch}.pdf');

        final threads = ref.read(settingsControllerProvider).compressionThreads;
        final successPath = await ToolsService.compressPdf(paths.first, outputPath, quality: quality, maxThreads: threads);

        if (!context.mounted) return;
        Navigator.of(context).pop(); // hide loading
        if (successPath != null) {
          showDialog(
            context: context,
            builder: (context) => ToolActionDialog(title: 'Success', message: 'PDF compressed successfully!\nSaved to: $successPath', isLoading: false, outputPath: successPath),
          );
        } else {
          showDialog(
            context: context,
            builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to compress PDF.', isLoading: false),
          );
        }
      } else {
        // Batch scenario
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ToolActionDialog(title: 'Batch Compressing', message: 'Compressing ${paths.length} files. This may take a while...', isLoading: true),
        );

        final dir = await ToolsDirectoryUtil.getDefaultOutputDirectory();
        final threads = ref.read(settingsControllerProvider).compressionThreads;

        final results = await Future.wait(paths.map((path) async {
          final originalName = p.basenameWithoutExtension(path);
          final outputPath = p.join(dir, '${originalName}_compressed.pdf');
          return await ToolsService.compressPdf(path, outputPath, quality: quality, maxThreads: threads);
        }));

        int successCount = results.where((path) => path != null).length;

        if (!context.mounted) return;
        Navigator.of(context).pop(); // hide loading

        showDialog(
          context: context,
          builder: (context) => ToolActionDialog(
            title: 'Batch Compression Complete',
            message: 'Successfully compressed $successCount out of ${paths.length} files.\nSaved to: $dir',
            isLoading: false,
            outputPath: dir // Open directory
          ),
        );
      }
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
