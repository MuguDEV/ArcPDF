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
    this.outputFiles,
  });

  final String title;
  final String message;
  final bool isLoading;
  final String? outputPath;
  final List<String>? outputFiles;

  @override
  State<ToolActionDialog> createState() => _ToolActionDialogState();
}

class _ToolActionDialogState extends State<ToolActionDialog> {
  bool _hasVibrated = false;
  bool _isActing = false;
  String? _actionError;

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

  Future<void> _performAction(Future<void> Function() action) async {
    setState(() {
      _isActing = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _actionError =
            'Unable to open or share the saved output. It may have been moved or deleted.');
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _share() => _performAction(() async {
        final path = widget.outputPath!;
        final files = <XFile>[];
        if (widget.outputFiles != null) {
          for (final file in widget.outputFiles!) {
            if (!await File(file).exists()) throw StateError('Missing output');
            files.add(XFile(file));
          }
        } else if (await Directory(path).exists()) {
          await for (final entity in Directory(path).list()) {
            if (entity is File) files.add(XFile(entity.path));
          }
          files.sort((a, b) => a.path.compareTo(b.path));
        } else if (await File(path).exists()) {
          files.add(XFile(path));
        }
        if (files.isEmpty) throw StateError('No output files');
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
          files: files,
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ));
      });

  Future<void> _openInApp() => _performAction(() async {
        final path = widget.outputPath!;
        if (p.extension(path).toLowerCase() == '.pdf' &&
            await File(path).exists()) {
          final item = PdfFileItem.fromFile(File(path));
          if (!mounted) return;
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.push(MaterialPageRoute<void>(
              builder: (_) => PdfViewerScreen(item: item)));
          return;
        }
        final result = await OpenFile.open(path);
        if (result.type != ResultType.done) throw StateError(result.message);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuccess = !widget.isLoading && widget.outputPath != null;
    final isError = !widget.isLoading && widget.outputPath == null;

    return PopScope(
      canPop: !widget.isLoading,
      child: Dialog(
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
                  color: isError
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: widget.isLoading
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: ArcProgressIndicator(),
                      )
                    : Icon(
                        isSuccess
                            ? HugeIcons.strokeRoundedCheckmarkBadge01
                            : HugeIcons.strokeRoundedAlert02,
                        size: 32,
                        color: isError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      )
                        .animate()
                        .scale(duration: 300.ms, curve: Curves.easeOutBack),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
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
              if (_actionError != null) ...[
                Text(_actionError!,
                    style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
              ],
              Wrap(
                alignment: WrapAlignment.center,
                runSpacing: 8,
                children: [
                  if (isSuccess) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isActing ? null : _share,
                      icon:
                          const Icon(HugeIcons.strokeRoundedShare01, size: 20),
                      label: const Text('Share'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isActing ? null : _openInApp,
                      icon:
                          const Icon(HugeIcons.strokeRoundedFolder01, size: 20),
                      label: const Text('Open'),
                    ),
                  ],
                  if (isError)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Dismiss'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
