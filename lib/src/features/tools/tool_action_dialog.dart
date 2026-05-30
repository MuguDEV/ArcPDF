import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';

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
      _vibrate();
    }
  }

  @override
  void initState() {
    super.initState();
    final isSuccess = !widget.isLoading && widget.outputPath != null;
    if (isSuccess) {
      _hasVibrated = true;
      _vibrate();
    }
  }

  Future<void> _vibrate() async {
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 150); // slight haptic feedback on load
    }
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
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          if (isSuccess)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(HugeIcons.strokeRoundedCheckmarkBadge01, color: Colors.green, size: 24),
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
            onPressed: () {
              Navigator.of(context).pop();
              if (widget.outputPath != null) {
                 OpenFile.open(widget.outputPath!);
              }
            },
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
