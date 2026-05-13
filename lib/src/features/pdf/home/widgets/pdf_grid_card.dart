import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/pdf_library_controller.dart';
import '../../domain/pdf_file_item.dart';
import 'pdf_thumbnail.dart';

class PdfGridCard extends ConsumerStatefulWidget {
  const PdfGridCard({
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
  ConsumerState<PdfGridCard> createState() => _PdfGridCardState();
}

class _PdfGridCardState extends ConsumerState<PdfGridCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFav = ref.watch(pdfLibraryControllerProvider.select((s) => s.favorites.contains(widget.item.path)));

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onFavorite,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    child: AspectRatio(
                      aspectRatio: 0.75,
                      child: PdfThumbnail(path: widget.item.path, isEncrypted: widget.item.isEncrypted, isCorrupted: widget.item.isCorrupted),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                      color: isFav ? theme.colorScheme.primary : Colors.white.withValues(alpha: 0.8),
                      iconSize: 20,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.25),
                        padding: const EdgeInsets.all(8),
                      ),
                      onPressed: widget.onFavorite,
                    ),
                  ),
                ],
              ),
              // Info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.MMMd().format(widget.item.lastModified),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
