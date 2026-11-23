import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../settings/haptic_service.dart';
import '../../../settings/settings_controller.dart';
import '../../application/pdf_library_controller.dart';
import '../../domain/pdf_file_item.dart';
import 'pdf_thumbnail.dart';
import 'peek_overlay.dart';
import '../../../../shared/theme/arc_theme.dart';

class PdfCustomCard extends ConsumerStatefulWidget {
  const PdfCustomCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    required this.onFavorite,
    this.onVault,
    this.onLongPress,
    this.scrollController,
    this.selectionMode = false,
    this.selected = false,
  });

  final PdfFileItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onVault;
  final VoidCallback? onLongPress;
  final ScrollController? scrollController;
  final bool selectionMode;
  final bool selected;

  @override
  ConsumerState<PdfCustomCard> createState() => _PdfCustomCardState();
}

class _PdfCustomCardState extends ConsumerState<PdfCustomCard> {
  final GlobalKey _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isFav = ref.watch(pdfLibraryControllerProvider
        .select((s) => s.favorites.contains(widget.item.path)));
    final tags = ref.watch(pdfLibraryControllerProvider
        .select((s) => s.tags[widget.item.path] ?? []));
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd().format(widget.item.lastModified);

    final settings = ref.watch(settingsControllerProvider);
    final lowPowerMode = settings.lowPowerMode;
    final reduceMotion =
        lowPowerMode || MediaQuery.disableAnimationsOf(context);
    final expandedLayout = MediaQuery.textScalerOf(context).scale(16) > 24;

    Widget innerContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Flex(
        direction: expandedLayout ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: expandedLayout
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          // Thumbnail
          SizedBox(
            width: 52,
            height: 72,
            child: PdfThumbnail(
                path: widget.item.path,
                cacheVersion:
                    '${widget.item.sizeBytes}-${widget.item.lastModified.microsecondsSinceEpoch}',
                isEncrypted: widget.item.isEncrypted,
                isCorrupted: widget.item.isCorrupted),
          ),
          SizedBox(width: 12, height: expandedLayout ? 12 : 0),

          // Info Section
          Flexible(
            flex: expandedLayout ? 0 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.item.name
                      .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: MediaQuery.textScalerOf(context).scale(16) > 24
                      ? null
                      : 2,
                  overflow: MediaQuery.textScalerOf(context).scale(16) > 24
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Location label
                Row(
                  children: [
                    Icon(ArcIcons.folder,
                        size: 12, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.item.locationLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines:
                            MediaQuery.textScalerOf(context).scale(12) > 18
                                ? null
                                : 1,
                        overflow:
                            MediaQuery.textScalerOf(context).scale(12) > 18
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Badges and date reflow with enlarged text.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_fileSize(widget.item.sizeBytes),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                          if (widget.item.pageCount != null)
                            Text('${widget.item.pageCount} pages',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          if (widget.item.isEncrypted)
                            _Badge(
                                label: 'Locked',
                                icon: ArcIcons.lock,
                                theme: theme),
                          if (widget.item.isCorrupted)
                            _Badge(
                                label: 'Corrupt',
                                icon: ArcIcons.error,
                                theme: theme,
                                isError: true),
                          Text(
                            date,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          ...tags.map((t) => _Badge(
                              label: t, icon: ArcIcons.tag, theme: theme)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Flex(
            direction: expandedLayout ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reduceMotion && widget.onVault != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: widget.selectionMode
                      ? null
                      : IconButton(
                          tooltip: 'Move to Secure Vault',
                          onPressed: widget.onVault,
                          icon: const Icon(ArcIcons.lock, size: 22),
                        ),
                ),
              SizedBox(
                width: 48,
                height: 48,
                child: widget.selectionMode
                    ? Icon(
                        widget.selected
                            ? ArcIcons.selected
                            : ArcIcons.unselected,
                        size: 24,
                        color: widget.selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      )
                    : IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: isFav
                              ? theme.colorScheme.primary
                                  .withValues(alpha: 0.10)
                              : null,
                        ),
                        tooltip: isFav
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                        onPressed: () {
                          ref.read(hapticServiceProvider).selectionClick();
                          widget.onFavorite();
                        },
                        icon: Icon(
                          isFav ? ArcIcons.favoriteSelected : ArcIcons.favorite,
                          color: isFav
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );

    final decoration = BoxDecoration(
      color: widget.selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: widget.selected
            ? theme.colorScheme.primary
            : ArcContrast.isHigh(context)
                ? theme.colorScheme.outline
                : Colors.transparent,
        width: ArcContrast.isHigh(context) ? 2 : 1,
      ),
    );
    Widget cardContent = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        key: const ValueKey('pdf-card-surface'),
        decoration: decoration,
        child: innerContent,
      ),
    );

    void handleLongPress() {
      if (widget.onLongPress != null) {
        widget.onLongPress!.call();
        return;
      }
      ref.read(hapticServiceProvider).mediumImpact();
      OverlayEntry? entry;
      entry = OverlayEntry(
        builder: (context) => PeekOverlay(
          item: widget.item,
          onDismiss: () {
            if (entry?.mounted ?? false) entry?.remove();
          },
        ),
      );
      Overlay.of(context).insert(entry);
    }

    final interactiveCard = Semantics(
      label: widget.item.name,
      checked: widget.selectionMode ? widget.selected : null,
      button: true,
      onTap: widget.onTap,
      onLongPress: widget.selectionMode ? null : handleLongPress,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (!widget.selectionMode) {
              ref.read(hapticServiceProvider).selectionClick();
            }
            widget.onTap();
          },
          onLongPress: widget.selectionMode ? null : handleLongPress,
          child: widget.selectionMode
              ? ExcludeSemantics(child: cardContent)
              : cardContent,
        ),
      ),
    );

    // List callers own the spacing between rows. Reduced-motion and selection
    // modes avoid the horizontal action panes entirely.
    if (widget.selectionMode || reduceMotion) return interactiveCard;

    return Padding(
        key: _cardKey,
        padding: EdgeInsets.zero,
        child: Slidable(
          key: ValueKey(widget.item.path),
          closeOnScroll: true,
          startActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.25,
            openThreshold: 0.1,
            closeThreshold: 0.1,
            children: [
              CustomSlidableAction(
                onPressed: (_) {
                  ref.read(hapticServiceProvider).selectionClick();
                  widget.onFavorite();
                },
                backgroundColor: Colors.transparent,
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isFav
                        ? theme.colorScheme.surfaceContainerHigh
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isFav
                            ? theme.colorScheme.outlineVariant
                            : theme.colorScheme.primary.withValues(alpha: 0.5),
                        width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isFav ? ArcIcons.favorite : ArcIcons.favoriteSelected,
                    color: isFav
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
          endActionPane: widget.onVault != null
              ? ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: 0.25,
                  openThreshold: 0.1,
                  closeThreshold: 0.1,
                  children: [
                    CustomSlidableAction(
                      onPressed: (_) {
                        ref.read(hapticServiceProvider).mediumImpact();
                        widget.onVault?.call();
                      },
                      backgroundColor: Colors.transparent,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                              width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          ArcIcons.lock,
                          color: theme.colorScheme.onSurface,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                )
              : null,
          child: RepaintBoundary(
            child: interactiveCard,
          ),
        ));
  }

  String _fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.label,
      required this.icon,
      required this.theme,
      this.isError = false});
  final String label;
  final IconData icon;
  final ThemeData theme;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isError
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isError
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
