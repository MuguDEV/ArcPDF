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

    return AlertDialog(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      title: Row(
        children: [
          if (widget.isLoading)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: ArcProgressIndicator(),
              ),
            ),
          if (isSuccess)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(HugeIcons.strokeRoundedCheckmarkBadge01, color: theme.colorScheme.onPrimaryContainer, size: 24),
            ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
          if (isError)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(HugeIcons.strokeRoundedAlert02, color: theme.colorScheme.error, size: 24),
            ).animate().shake(duration: 300.ms),
          const SizedBox(width: 16),
          Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
      actions: [
        if (isSuccess) ...[
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (widget.outputPath != null) {
                 Share.shareXFiles([XFile(widget.outputPath!)]);
              }
            },
            child: const Text('Share'),
          ),
          FilledButton(
            onPressed: _openInApp,
            child: const Text('Open'),
          ),
        ],
        if (isError)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}
