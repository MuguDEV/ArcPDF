import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../settings/settings_controller.dart';
import '../../application/pdf_library_controller.dart';
import '../../domain/pdf_file_item.dart';
import 'pdf_thumbnail.dart';

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

    return InkWell(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onFavorite,
      splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
      highlightColor: Colors.transparent,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: Duration(milliseconds: (120 ~/ animSpeed)),
        curve: Curves.fastLinearToSlowEaseIn,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Thumbnail
              RepaintBoundary(
                child: SizedBox(
                  width: 56,
                  height: 72,
                  child: Hero(
                    tag: 'pdf_thumb_${widget.item.path}',
                    child: PdfThumbnail(path: widget.item.path, isEncrypted: widget.item.isEncrypted, isCorrupted: widget.item.isCorrupted),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Metadata Date
                    Text(
                      date,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // Metadata chips row
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Badge(label: _fileSize(widget.item.sizeBytes), theme: theme),
                        if (widget.item.locationLabel.isNotEmpty && widget.item.locationLabel != 'Storage')
                          _Badge(label: widget.item.locationLabel, theme: theme),
                        if (widget.item.pageCount != null)
                          _Badge(label: '${widget.item.pageCount} pages', theme: theme),
                        if (widget.item.isEncrypted)
                          _Badge(label: 'Locked', theme: theme),
                        if (widget.item.isCorrupted)
                          _Badge(label: 'Corrupt', theme: theme, isError: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Trailing action (like favorite or a menu)
              IconButton(
                key: ValueKey(isFav),
                onPressed: widget.onFavorite,
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
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
  const _Badge({required this.label, required this.theme, this.isError = false});
  final String label;
  final ThemeData theme;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    // We explicitly use standard container with minimal padding instead of M3 FilterChip
    // to keep it tight and avoid text layout clipping bugs.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isError ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
    );
  }
}
