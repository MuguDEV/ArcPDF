import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../settings/settings_controller.dart';
import '../../application/pdf_library_controller.dart';
import '../../domain/pdf_file_item.dart';
import 'pdf_thumbnail.dart';
import 'rename_dialog.dart';

class PdfCard extends ConsumerStatefulWidget {
  const PdfCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    required this.onFavorite,
  });

  final PdfFileItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  ConsumerState<PdfCard> createState() => _PdfCardState();
}

class _PdfCardState extends ConsumerState<PdfCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isFav = ref.watch(pdfLibraryControllerProvider.select((s) => s.favorites.contains(widget.item.path)));
    final animSpeed = ref.watch(pdfLibraryControllerProvider.select((_) => ref.watch(settingsControllerProvider).animationSpeed));
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd().format(widget.item.lastModified);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onFavorite,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: Duration(milliseconds: (120 ~/ animSpeed)),
          curve: Curves.fastLinearToSlowEaseIn,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              color: theme.colorScheme.surfaceContainerLow,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  RepaintBoundary(
                    child: SizedBox(
                      width: 72,
                      height: 96,
                      child: PdfThumbnail(path: widget.item.path, isEncrypted: widget.item.isEncrypted, isCorrupted: widget.item.isCorrupted),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Metadata chips row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _Badge(label: _fileSize(widget.item.sizeBytes), theme: theme),
                            _Badge(label: widget.item.locationLabel, theme: theme),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          date,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (widget.item.pageCount != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${widget.item.pageCount} pages',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Actions
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey(isFav),
                        onPressed: widget.onFavorite,
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? Colors.grey.shade400 : null,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Share.shareXFiles([XFile(widget.item.path)]),
                        icon: const Icon(HugeIcons.strokeRoundedShare01, size: 20),
                      ),
                      IconButton(
                        onPressed: () async {
                          final newName = await showRenameDialog(context, widget.item.name);
                          if (newName != null && newName.isNotEmpty && mounted) {
                            final success = await ref.read(pdfLibraryControllerProvider.notifier).renameFile(widget.item, newName);
                            if (!success && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Failed to rename file.')),
                              );
                            }
                          }
                        },
                        icon: const Icon(HugeIcons.strokeRoundedEdit02, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.theme});
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
