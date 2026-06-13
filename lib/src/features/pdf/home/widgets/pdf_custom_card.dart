import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../settings/haptic_service.dart';
import '../../../settings/settings_controller.dart';
import '../../application/pdf_library_controller.dart';
import '../../domain/pdf_file_item.dart';
import 'pdf_thumbnail.dart';
import 'peek_overlay.dart';
import '../../../../shared/widgets/arc_bouncy_card.dart';
import '../../../../shared/widgets/parallax_wrapper.dart';

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
  });

  final PdfFileItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onVault;
  final VoidCallback? onLongPress;
  final ScrollController? scrollController;

  @override
  ConsumerState<PdfCustomCard> createState() => _PdfCustomCardState();
}

class _PdfCustomCardState extends ConsumerState<PdfCustomCard> {
  final GlobalKey _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isFav = ref.watch(pdfLibraryControllerProvider.select((s) => s.favorites.contains(widget.item.path)));
    final tags = ref.watch(pdfLibraryControllerProvider.select((s) => s.tags[widget.item.path] ?? []));
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd().format(widget.item.lastModified);
    final time = DateFormat.jm().format(widget.item.lastModified);
    final isDark = theme.brightness == Brightness.dark;
    final lowPowerMode = ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));

    Widget innerContent = Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Thumbnail
                  Hero(
                    tag: 'pdf_thumb_${widget.item.path}',
                    flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                       return FadeTransition(
                         opacity: animation,
                         child: toHeroContext.widget,
                       );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 60,
                        height: 80,
                        child: widget.scrollController != null
                          ? ParallaxWrapper(
                              scrollController: widget.scrollController!,
                              listItemKey: _cardKey,
                              parallaxSpeed: 0.15,
                              child: PdfThumbnail(path: widget.item.path, isEncrypted: widget.item.isEncrypted, isCorrupted: widget.item.isCorrupted),
                            )
                          : PdfThumbnail(path: widget.item.path, isEncrypted: widget.item.isEncrypted, isCorrupted: widget.item.isCorrupted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Info Section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Favorite Button integrated in the top right with spring micro-interaction
                            GestureDetector(
                              onTap: () {
                                ref.read(hapticServiceProvider).selectionClick();
                                widget.onFavorite();
                              },
                              child: Icon(
                                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: isFav ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                size: 22,
                              ).animate(key: ValueKey(isFav)).scale(
                                begin: const Offset(0.5, 0.5),
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.elasticOut,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Location label
                        Row(
                          children: [
                            Icon(HugeIcons.strokeRoundedFolder01, size: 12, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.item.locationLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Badges perfectly aligned + date
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _Badge(label: _fileSize(widget.item.sizeBytes), icon: HugeIcons.strokeRoundedHardDrive, theme: theme),
                                  if (widget.item.pageCount != null)
                                    _Badge(label: '${widget.item.pageCount}p', icon: HugeIcons.strokeRoundedFile01, theme: theme),
                                  if (widget.item.isEncrypted)
                                    _Badge(label: 'Locked', icon: HugeIcons.strokeRoundedLockPassword, theme: theme),
                                  if (widget.item.isCorrupted)
                                    _Badge(label: 'Corrupt', icon: HugeIcons.strokeRoundedAlert02, theme: theme, isError: true),
                                  ...tags.map((t) => _Badge(label: t, icon: HugeIcons.strokeRoundedTag01, theme: theme)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  date,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  time,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
      ),
    );

    Widget cardContent = ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: lowPowerMode ? Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1.0,
              ),
            ),
            child: innerContent,
        ) : BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1.0,
              ),
            ),
            child: innerContent,
          ),
        ),
    );

    return Padding(
      key: _cardKey,
      padding: const EdgeInsets.only(bottom: 12),
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
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: isFav ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isFav ? theme.colorScheme.outlineVariant : theme.colorScheme.primary.withValues(alpha: 0.5), width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isFav ? HugeIcons.strokeRoundedFavourite : Icons.favorite_rounded,
                  color: isFav ? theme.colorScheme.onSurface : theme.colorScheme.primary,
                  size: 28,
                ).animate(key: ValueKey(isFav)).scale(
                  begin: const Offset(0.5, 0.5),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                ),
              ),
            ),
          ],
        ),
        endActionPane: widget.onVault != null ? ActionPane(
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
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(
                  HugeIcons.strokeRoundedSafe,
                  color: theme.colorScheme.onSurface,
                  size: 28,
                ).animate().scale(
                  begin: const Offset(0.5, 0.5),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                ),
              ),
            ),
          ],
        ) : null,
        child: RepaintBoundary(
          child: ArcBouncyCard(
            onTap: () {
              ref.read(hapticServiceProvider).selectionClick();
              widget.onTap();
            },
            onLongPress: () {
              // Custom injected long press (e.g., selection mode) wins over Peek
              if (widget.onLongPress != null) {
                widget.onLongPress!.call();
                return;
              }

              // Peek overlay
              ref.read(hapticServiceProvider).mediumImpact();
              OverlayEntry? entry;
              entry = OverlayEntry(
                builder: (context) => PeekOverlay(
                  item: widget.item,
                  onDismiss: () {
                    entry?.remove();
                  },
                ),
              );
              Overlay.of(context).insert(entry);
            },
            child: cardContent,
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
  const _Badge({required this.label, required this.icon, required this.theme, this.isError = false});
  final String label;
  final IconData icon;
  final ThemeData theme;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isError ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
