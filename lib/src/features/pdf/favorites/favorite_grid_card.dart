import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/pdf_library_controller.dart';
import '../domain/pdf_file_item.dart';
import '../home/widgets/pdf_thumbnail.dart';
import '../../settings/haptic_service.dart';
import '../../../shared/widgets/arc_bouncy_card.dart';

class FavoriteGridCard extends ConsumerStatefulWidget {
  const FavoriteGridCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    required this.onUnfavorite,
  });
  final PdfFileItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onUnfavorite;

  @override
  ConsumerState<FavoriteGridCard> createState() => _FavoriteGridCardState();
}

class _FavoriteGridCardState extends ConsumerState<FavoriteGridCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = ref.watch(pdfLibraryControllerProvider);
    final isFav = lib.favorites.contains(widget.item.path);

    return ArcBouncyCard(
      onTap: () {
        ref.read(hapticServiceProvider).selectionClick();
        widget.onTap();
      },
      onLongPress: () async {
        ref.read(hapticServiceProvider).lightImpact();
        widget.onUnfavorite();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Removed from favorites'),
              action: SnackBarAction(label: 'Undo', onPressed: () => ref.read(pdfLibraryControllerProvider.notifier).toggleFavorite(widget.item)),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          );
        }
      },
      child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: AspectRatio(
                  aspectRatio: 0.75,
                  child: PdfThumbnail(path: widget.item.path, isEncrypted: widget.item.isEncrypted, isCorrupted: widget.item.isCorrupted),
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.name.replaceAll('.pdf', '').replaceAll('.PDF', ''),
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
                    if (isFav)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.favorite_rounded, size: 14, color: Colors.grey.shade400),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}
