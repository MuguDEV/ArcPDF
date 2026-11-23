import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/haptic_service.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

import '../pdf/viewer/pdf_viewer_screen.dart';
import '../pdf/domain/pdf_file_item.dart';
import '../pdf/home/widgets/pdf_thumbnail.dart';
import 'job_queue.dart';

enum ToolResultKind { generic, compression, merge }

class ToolActionDialog extends ConsumerStatefulWidget {
  const ToolActionDialog({
    super.key,
    required this.title,
    required this.message,
    required this.isLoading,
    this.outputPath,
    this.outputFiles,
    this.progress,
    this.onCancel,
    this.inputPaths,
    this.resultKind = ToolResultKind.generic,
  });

  final String title;
  final String message;
  final bool isLoading;
  final String? outputPath;
  final List<String>? outputFiles;
  final JobProgress? progress;
  final VoidCallback? onCancel;
  final List<String>? inputPaths;
  final ToolResultKind resultKind;

  @override
  ConsumerState<ToolActionDialog> createState() => _ToolActionDialogState();
}

class _ToolActionDialogState extends ConsumerState<ToolActionDialog> {
  bool _hasVibrated = false;
  bool _isActing = false;
  String? _actionError;
  Future<_ToolResultStats?>? _resultStats;

  @override
  void didUpdateWidget(covariant ToolActionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isLoading && oldWidget.outputPath != null) {
      // Already success, skip
      return;
    }

    final isSuccess = !widget.isLoading && widget.outputPath != null;
    if (isSuccess &&
        (oldWidget.outputPath != widget.outputPath ||
            oldWidget.outputFiles != widget.outputFiles)) {
      _resultStats = _loadResultStats();
    }
    if (isSuccess && !_hasVibrated) {
      _hasVibrated = true;
      ref.read(hapticServiceProvider).lightImpact();
    }
  }

  @override
  void initState() {
    super.initState();
    final isSuccess = !widget.isLoading && widget.outputPath != null;
    if (isSuccess) {
      _hasVibrated = true;
      ref.read(hapticServiceProvider).lightImpact();
      _resultStats = _loadResultStats();
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

  Future<_ToolResultStats?> _loadResultStats() async {
    final outputPath = widget.outputPath;
    if (outputPath == null) return null;
    final inputs = widget.inputPaths ?? const <String>[];
    final outputs = widget.outputFiles?.isNotEmpty == true
        ? widget.outputFiles!
        : <String>[outputPath];
    var inputBytes = 0;
    var outputBytes = 0;
    var outputCount = 0;
    String? previewPath;
    String? outputName;
    for (final path in inputs) {
      final file = File(path);
      if (await file.exists()) inputBytes += await file.length();
    }
    for (final path in outputs) {
      final file = File(path);
      if (!await file.exists()) continue;
      outputBytes += await file.length();
      outputCount++;
      outputName ??= p.basename(path);
      if (previewPath == null && p.extension(path).toLowerCase() == '.pdf') {
        previewPath = path;
      }
    }
    if (outputCount == 0) return null;
    return _ToolResultStats(
      inputBytes: inputBytes,
      outputBytes: outputBytes,
      outputCount: outputCount,
      previewPath: outputCount == 1 ? previewPath : null,
      outputName: outputCount == 1 ? outputName : null,
    );
  }

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
        child: SingleChildScrollView(
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
                    ? SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          value: widget.progress?.percentage,
                          strokeWidth: 3,
                        ),
                      )
                    : Icon(
                        isSuccess ? ArcIcons.success : ArcIcons.error,
                        size: 32,
                        color: isError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (isSuccess && _resultStats != null) ...[
                const SizedBox(height: 16),
                FutureBuilder<_ToolResultStats?>(
                  future: _resultStats,
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    if (stats == null) {
                      return snapshot.connectionState == ConnectionState.done
                          ? const SizedBox.shrink()
                          : Text(
                              'Calculating final file size…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                    }
                    return _ToolResultPreview(
                      stats: stats,
                      kind: widget.resultKind,
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (widget.isLoading && widget.progress != null) ...[
                const SizedBox(height: 10),
                Text(
                    '${(widget.progress!.percentage * 100).round()}% · ${widget.progress!.stage}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
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
                  if (widget.isLoading && widget.onCancel != null)
                    TextButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel'),
                    ),
                  if (isSuccess) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isActing ? null : _share,
                      icon: const Icon(ArcIcons.share, size: 20),
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
                      icon: const Icon(ArcIcons.folder, size: 20),
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
        )),
      ),
    );
  }
}

class _ToolResultStats {
  const _ToolResultStats({
    required this.inputBytes,
    required this.outputBytes,
    required this.outputCount,
    this.previewPath,
    this.outputName,
  });

  final int inputBytes;
  final int outputBytes;
  final int outputCount;
  final String? previewPath;
  final String? outputName;
}

class _ToolResultPreview extends StatelessWidget {
  const _ToolResultPreview({required this.stats, required this.kind});

  final _ToolResultStats stats;
  final ToolResultKind kind;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final difference = stats.inputBytes - stats.outputBytes;
    final percentage = stats.inputBytes == 0
        ? null
        : (difference.abs() / stats.inputBytes * 100).round();
    final changeLabel = difference > 0
        ? '${_formatBytes(difference)} smaller${percentage == null ? '' : ' ($percentage%)'}'
        : difference < 0
            ? '${_formatBytes(-difference)} larger${percentage == null ? '' : ' ($percentage%)'}'
            : 'Same size';
    return Semantics(
      container: true,
      label: 'Saved PDF result',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stats.previewPath != null)
              PdfThumbnail(path: stats.previewPath!)
            else
              SizedBox(
                width: 52,
                height: 72,
                child: Icon(
                  stats.outputCount > 1 ? ArcIcons.copy : ArcIcons.pdf,
                  color: theme.colorScheme.primary,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stats.outputCount == 1
                        ? (stats.outputName ?? 'Saved PDF')
                        : '${stats.outputCount} output files',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  if (stats.inputBytes > 0)
                    Text('Input  ${_formatBytes(stats.inputBytes)}',
                        style: theme.textTheme.bodySmall),
                  Text('Output  ${_formatBytes(stats.outputBytes)}',
                      style: theme.textTheme.bodySmall),
                  if (stats.inputBytes > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      kind == ToolResultKind.merge
                          ? 'Compared with combined inputs: $changeLabel'
                          : changeLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: difference > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
