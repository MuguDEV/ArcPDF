import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../settings/settings_controller.dart';
import '../settings/haptic_service.dart';
import 'widgets/tool_card.dart';
import 'tools_service.dart';
import 'tool_action_dialog.dart';
import 'pages/merge_pdfs_page.dart';
import 'pages/split_pdf_page.dart';
import 'pages/images_to_pdf_page.dart';
import 'pages/pdf_to_images_page.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;
    final isBlur = settings.useBlurEffect;
    final isLiquid = settings.useLiquidGlass;
    final double sigma = isLiquid ? 48.0 : 16.0;
    final Color bgColor = isLiquid
        ? (isDark ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4))
        : theme.colorScheme.surface.withValues(alpha: isBlur ? 0.7 : 1.0);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: bgColor,
            flexibleSpace: isBlur
                ? ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: Container(color: Colors.transparent),
                    ),
                  )
                : null,
            title: const Text('Tools', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            sliver: SliverList.list(
              children: [
                _buildSectionHeader('PDF Utilities', context).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 12),
                ToolCard(
                  title: 'Merge PDFs',
                  subtitle: 'Combine and reorder multiple PDF files',
                  icon: HugeIcons.strokeRoundedLayers01,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MergePdfsPage()));
                  },
                ).animate(delay: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                const SizedBox(height: 12),
                ToolCard(
                  title: 'Split PDF',
                  subtitle: 'Extract pages from a PDF and save as new files',
                  icon: HugeIcons.strokeRoundedScissor01,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SplitPdfPage()));
                  },
                ).animate(delay: 100.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                const SizedBox(height: 12),
                ToolCard(
                  title: 'Compress PDF',
                  subtitle: 'Reduce the file size of your PDF document',
                  icon: HugeIcons.strokeRoundedFile01,
                  onTap: () => _handleCompress(context, ref),
                ).animate(delay: 150.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),

                const SizedBox(height: 32),
                _buildSectionHeader('Conversion', context).animate(delay: 200.ms).fadeIn(duration: 300.ms),
                const SizedBox(height: 12),
                ToolCard(
                  title: 'Images to PDF',
                  subtitle: 'Convert, reorder, and combine images into a PDF',
                  icon: HugeIcons.strokeRoundedImage01,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImagesToPdfPage()));
                  },
                ).animate(delay: 250.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                const SizedBox(height: 12),
                ToolCard(
                  title: 'PDF to Images',
                  subtitle: 'Extract and save each page of a PDF as an image',
                  icon: HugeIcons.strokeRoundedImage02,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PdfToImagesPage()));
                  },
                ).animate(delay: 300.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),

                const SizedBox(height: 120), // Bottom padding for nav bar
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCompress(BuildContext context, WidgetRef ref) async {
    ref.read(hapticServiceProvider).lightImpact();
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.paths.isNotEmpty) {
      final inputPath = result.paths.first!;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const ToolActionDialog(title: 'Compressing PDF', message: 'Applying best compression settings...', isLoading: true),
      );

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = p.join(dir.path, 'Compressed_${DateTime.now().millisecondsSinceEpoch}.pdf');

      final successPath = await ToolsService.compressPdf(inputPath, outputPath);
      Navigator.of(context).pop(); // hide loading
      if (successPath != null) {
        showDialog(
          context: context,
          builder: (context) => ToolActionDialog(title: 'Success', message: 'PDF compressed successfully!\nSaved to: $successPath', isLoading: false),
        );
      } else {
        showDialog(
          context: context,
          builder: (context) => const ToolActionDialog(title: 'Error', message: 'Failed to compress PDF.', isLoading: false),
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
