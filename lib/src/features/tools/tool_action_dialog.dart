import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

import '../pdf/viewer/pdf_viewer_screen.dart';
import '../pdf/domain/pdf_file_item.dart';
import '../../shared/widgets/arc_progress_indicator.dart';

class ToolActionDialog extends StatefulWidget {
  const ToolActionDialog({
    super.key,
    required this.title,
    required this.message,
    required this.isLoading,
    this.outputPath,
  });

  final String title;
  final String message;
  final bool isLoading;
  final String? outputPath;

  @override
  State<ToolActionDialog> createState() => _ToolActionDialogState();
}

class _ToolActionDialogState extends State<ToolActionDialog> {
  bool _hasVibrated = false;

  @override
  void didUpdateWidget(covariant ToolActionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isLoading && oldWidget.outputPath != null) {
      // Already success, skip
      return;
    }

    final isSuccess = !widget.isLoading && widget.outputPath != null;
    if (isSuccess && !_hasVibrated) {
      _hasVibrated = true;
      HapticFeedback.lightImpact();
    }
  }

  @override
  void initState() {
    super.initState();
    final isSuccess = !widget.isLoading && widget.outputPath != null;
    if (isSuccess) {
      _hasVibrated = true;
      HapticFeedback.lightImpact();
    }
  }

  void _openInApp() {
    if (widget.outputPath == null) return;

    // Check if it's a PDF before opening in viewer
    if (p.extension(widget.outputPath!).toLowerCase() == '.pdf') {
       final file = File(widget.outputPath!);
       if (file.existsSync()) {
          final tempItem = PdfFileItem.fromFile(file);
          Navigator.of(context).pop();
          Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(item: tempItem)));
          return;
       }
    }

    // Fallback for directories or non-PDFs (like PDF to Images output dir)
    Navigator.of(context).pop();
    OpenFile.open(widget.outputPath!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuccess = !widget.isLoading && widget.outputPath != null;
    final isError = !widget.isLoading && widget.outputPath == null;

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
                color: isError ? theme.colorScheme.errorContainer : theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: widget.isLoading
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: ArcProgressIndicator(),
                    )
                  : Icon(
                      isSuccess ? HugeIcons.strokeRoundedCheckmarkBadge01 : HugeIcons.strokeRoundedAlert02,
                      size: 32,
                      color: isError ? theme.colorScheme.error : theme.colorScheme.primary,
                    ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSuccess) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (widget.outputPath != null) {
                         Share.shareXFiles([XFile(widget.outputPath!)]);
                      }
                    },
                    icon: const Icon(HugeIcons.strokeRoundedShare01, size: 20),
                    label: const Text('Share'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _openInApp,
                    icon: const Icon(HugeIcons.strokeRoundedFolder01, size: 20),
                    label: const Text('Open'),
                  ),
                ],
                if (isError)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
