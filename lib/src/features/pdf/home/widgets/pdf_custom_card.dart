import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import '../../../../shared/widgets/particle_burst.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import '../../../../shared/theme/arc_colors.dart';

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
  final GlobalKey<ParticleBurstState> _burstKey =
      GlobalKey<ParticleBurstState>();

  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  double _tiltX = 0;
  double _tiltY = 0;

  @override
  void initState() {
    super.initState();
    _initGyro();
  }

  void _initGyro() {
    final settings = ref.read(settingsControllerProvider);
    if (settings.enableGyroCards) {
      _gyroSubscription =
          gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval)
              .listen((event) {
        if (mounted) {
          setState(() {
            // Apply smoothing and limit the tilt angles
            _tiltX += event.y * 0.05;
            _tiltY += event.x * 0.05;

            // Decaying spring back to zero
            _tiltX *= 0.95;
            _tiltY *= 0.95;

            // Clamp strictly
            _tiltX = _tiltX.clamp(-0.15, 0.15);
            _tiltY = _tiltY.clamp(-0.15, 0.15);
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant PdfCustomCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final settings = ref.read(settingsControllerProvider);
    if (settings.enableGyroCards && _gyroSubscription == null) {
      _initGyro();
    } else if (!settings.enableGyroCards && _gyroSubscription != null) {
      _gyroSubscription?.cancel();
      _gyroSubscription = null;
      setState(() {
        _tiltX = 0;
        _tiltY = 0;
      });
    }
  }

  @override
  void dispose() {
    _gyroSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFav = ref.watch(pdfLibraryControllerProvider
        .select((s) => s.favorites.contains(widget.item.path)));
    final tags = ref.watch(pdfLibraryControllerProvider
        .select((s) => s.tags[widget.item.path] ?? []));
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd().format(widget.item.lastModified);
    final time = DateFormat.jm().format(widget.item.lastModified);

    final settings = ref.watch(settingsControllerProvider);
    final lowPowerMode = settings.lowPowerMode;
    final reduceMotion =
        lowPowerMode || MediaQuery.disableAnimationsOf(context);

    Widget innerContent = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 72,
              child: PdfThumbnail(
                  path: widget.item.path,
                  isEncrypted: widget.item.isEncrypted,
                  isCorrupted: widget.item.isCorrupted),
            ),
          ),
          const SizedBox(width: 12),

          // Info Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.item.name
                      .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),

                // Location label
                Row(
                  children: [
                    Icon(HugeIcons.strokeRoundedFolder01,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.item.locationLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
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
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Badge(
                              label: _fileSize(widget.item.sizeBytes),
                              icon: HugeIcons.strokeRoundedHardDrive,
                              theme: theme),
                          if (widget.item.pageCount != null)
                            _Badge(
                                label: '${widget.item.pageCount}p',
                                icon: HugeIcons.strokeRoundedFile01,
                                theme: theme),
                          if (widget.item.isEncrypted)
                            _Badge(
                                label: 'Locked',
                                icon: HugeIcons.strokeRoundedLockPassword,
                                theme: theme),
                          if (widget.item.isCorrupted)
                            _Badge(
                                label: 'Corrupt',
                                icon: HugeIcons.strokeRoundedAlert02,
                                theme: theme,
                                isError: true),
                          Text(
                            '$date · $time',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          ...tags.map((t) => _Badge(
                              label: t,
                              icon: HugeIcons.strokeRoundedTag01,
                              theme: theme)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reduceMotion && widget.onVault != null)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: widget.selectionMode
                      ? null
                      : IconButton(
                          tooltip: 'Move to Secure Vault',
                          onPressed: widget.onVault,
                          icon:
                              const Icon(HugeIcons.strokeRoundedSafe, size: 22),
                        ),
                ),
              SizedBox(
                width: 44,
                height: 44,
                child: widget.selectionMode
                    ? Icon(
                        widget.selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 24,
                        color: widget.selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      )
                    : IconButton(
                        tooltip: isFav
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                        onPressed: () {
                          ref.read(hapticServiceProvider).selectionClick();
                          widget.onFavorite();
                        },
                        icon: Icon(
                          isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
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
      borderRadius: BorderRadius.circular(ArcColors.cardRadius),
      border: Border.all(
        color: widget.selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.1),
        width: 1.5,
      ),
    );
    Widget cardContent = ClipRRect(
      borderRadius: BorderRadius.circular(ArcColors.cardRadius),
      child: Container(
        decoration: decoration,
        child: innerContent,
      ),
    );

    // List callers own the spacing between rows.
    if (widget.selectionMode || reduceMotion) {
      return Padding(
        padding: EdgeInsets.zero,
        child: Semantics(
          label: widget.item.name,
          checked: widget.selectionMode ? widget.selected : null,
          button: true,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(ArcColors.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(ArcColors.cardRadius),
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: widget.selectionMode
                  ? ExcludeSemantics(child: cardContent)
                  : cardContent,
            ),
          ),
        ),
      );
    }

    return Padding(
        key: _cardKey,
        padding: EdgeInsets.zero,
        child: ParticleBurst(
          burstKey: _burstKey,
          burstColor: theme.colorScheme.primary,
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
                    if (!isFav) {
                      _burstKey.currentState?.triggerBurst();
                    }
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
                              : theme.colorScheme.primary
                                  .withValues(alpha: 0.5),
                          width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isFav
                          ? HugeIcons.strokeRoundedFavourite
                          : Icons.favorite_rounded,
                      color: isFav
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.primary,
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
                            borderRadius:
                                BorderRadius.circular(ArcColors.cardRadius),
                            border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                                width: 1),
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
                  )
                : null,
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
                        // Guard against the overlay already having been
                        // removed (e.g. if dismissal was triggered twice).
                        if (entry?.mounted ?? false) {
                          entry?.remove();
                        }
                      },
                    ),
                  );
                  Overlay.of(context).insert(entry);
                },
                child: cardContent,
              ),
            ),
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
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
