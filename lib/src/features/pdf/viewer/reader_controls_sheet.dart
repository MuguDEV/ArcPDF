import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme/arc_colors.dart';

enum ReaderLayoutMode { continuous, singlePage, twoPage }

enum ReaderAction {
  pageColors,
  favorite,
  fitWidth,
  fitPage,
  scrollDirection,
  rotate,
  fullscreen,
  autoScroll,
  keepAwake,
  thumbnails,
  outline,
  info,
  share,
  sharePage,
  print,
  layout,
  bookmarks,
  reflow,
  readingSettings,
  readAloud,
  annotate,
  selectText,
}

/// Content for a parent-constrained modal sheet. The caller owns action handling
/// and dismissal; only the close button dismisses this sheet directly.
class ReaderControlsSheet extends StatelessWidget {
  const ReaderControlsSheet({
    super.key,
    required this.title,
    required this.page,
    required this.pageCount,
    required this.ready,
    required this.darkPages,
    required this.isFavorite,
    required this.horizontalScroll,
    required this.autoScroll,
    required this.keepAwake,
    required this.fullscreen,
    required this.onSelected,
    this.layoutMode = ReaderLayoutMode.continuous,
    this.hasTextSelection = false,
  });

  final String title;
  final int page;
  final int pageCount;
  final bool ready;
  final bool darkPages;
  final bool isFavorite;
  final bool horizontalScroll;
  final bool autoScroll;
  final bool keepAwake;
  final bool fullscreen;
  final ValueChanged<ReaderAction> onSelected;
  final ReaderLayoutMode layoutMode;
  final bool hasTextSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;
    final background = theme.colorScheme.surface;
    final pageLabel = ready && pageCount > 0
        ? 'Page ${page.clamp(1, pageCount)} of $pageCount'
        : 'Document not ready';

    return Material(
      color: background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ArcColors.sheetRadius),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: FocusTraversalGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ExcludeSemantics(
                    child: Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius:
                            BorderRadius.circular(ArcColors.pillRadius),
                      ),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Reading controls',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close reading controls',
                      onPressed: () => Navigator.maybePop(context),
                      constraints: const BoxConstraints(
                        minWidth: ArcColors.minTouchTarget,
                        minHeight: ArcColors.minTouchTarget,
                      ),
                      color: foreground,
                      icon: const Icon(ArcIcons.close),
                    ),
                  ],
                ),
                Tooltip(
                  message: title,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pageLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const _SectionHeading('View'),
                _ActionGrid(children: [
                  _QuickAction(
                    action: ReaderAction.pageColors,
                    icon: darkPages ? ArcIcons.darkMode : ArcIcons.lightMode,
                    label: 'Page colors',
                    tooltip: 'Page colors: ${darkPages ? 'Dark' : 'Light'}',
                    selected: darkPages,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.fitWidth,
                    icon: ArcIcons.fitWidth,
                    label: 'Fit width',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.fitPage,
                    icon: ArcIcons.fitPage,
                    label: 'Fit page',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.scrollDirection,
                    icon: horizontalScroll
                        ? ArcIcons.horizontal
                        : ArcIcons.vertical,
                    label: 'Scroll direction',
                    tooltip: 'Scroll direction: '
                        '${horizontalScroll ? 'Horizontal' : 'Vertical'}',
                    selected: horizontalScroll,
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.rotate,
                    icon: ArcIcons.rotate,
                    label: 'Rotate',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.fullscreen,
                    icon: fullscreen
                        ? ArcIcons.exitFullscreen
                        : ArcIcons.fullscreen,
                    label: 'Fullscreen',
                    tooltip:
                        fullscreen ? 'Exit fullscreen' : 'Enter fullscreen',
                    selected: fullscreen,
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.layout,
                    icon: switch (layoutMode) {
                      ReaderLayoutMode.continuous => ArcIcons.layoutContinuous,
                      ReaderLayoutMode.singlePage => ArcIcons.layoutSingle,
                      ReaderLayoutMode.twoPage => ArcIcons.layoutTwoPage,
                    },
                    label: switch (layoutMode) {
                      ReaderLayoutMode.continuous => 'Continuous',
                      ReaderLayoutMode.singlePage => 'Single page',
                      ReaderLayoutMode.twoPage => 'Two pages',
                    },
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                ]),
                const _SectionHeading('Reading'),
                // Material owns the ink for every ListTile, including in apps
                // whose ListTileTheme requests a tile background color.
                Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(ArcColors.buttonRadius),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ReadingToggle(
                        action: ReaderAction.autoScroll,
                        icon: ArcIcons.autoScroll,
                        label: 'Auto scroll',
                        value: autoScroll,
                        enabled: ready,
                        onSelected: onSelected,
                      ),
                      _ReadingToggle(
                        action: ReaderAction.keepAwake,
                        icon: ArcIcons.keepAwake,
                        label: 'Keep awake',
                        value: keepAwake,
                        onSelected: onSelected,
                      ),
                      _ReadingToggle(
                        action: ReaderAction.favorite,
                        icon: isFavorite
                            ? ArcIcons.favoriteSelected
                            : ArcIcons.favorite,
                        label: 'Favorite',
                        value: isFavorite,
                        onSelected: onSelected,
                      ),
                    ],
                  ),
                ),
                const _SectionHeading('Document'),
                _ActionGrid(children: [
                  _QuickAction(
                    action: ReaderAction.bookmarks,
                    icon: ArcIcons.bookmark,
                    label: 'Marks',
                    tooltip: 'Bookmarks',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.reflow,
                    icon: ArcIcons.reflow,
                    label: 'Reflow',
                    tooltip: 'Reflow text',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.readingSettings,
                    icon: ArcIcons.textSize,
                    label: 'Text',
                    tooltip: 'Text settings',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.readAloud,
                    icon: ArcIcons.speak,
                    label: 'Speak',
                    tooltip: 'Read aloud',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.annotate,
                    icon: ArcIcons.annotate,
                    label: 'Mark',
                    tooltip: 'Annotate',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.selectText,
                    icon: ArcIcons.selectAll,
                    label: 'Select',
                    tooltip: 'Select text',
                    enabled: ready,
                    selected: hasTextSelection,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.thumbnails,
                    icon: ArcIcons.grid,
                    label: 'Pages',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.outline,
                    icon: ArcIcons.outline,
                    label: 'Outline',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.info,
                    icon: ArcIcons.info,
                    label: 'Info',
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.share,
                    icon: ArcIcons.share,
                    label: 'Share PDF',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.sharePage,
                    icon: ArcIcons.export,
                    label: 'Share page image',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                  _QuickAction(
                    action: ReaderAction.print,
                    icon: ArcIcons.print,
                    label: 'Print',
                    enabled: ready,
                    onSelected: onSelected,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Semantics(
          header: true,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      );
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final effectiveWidth = constraints.maxWidth / scale;
          final columns = effectiveWidth >= 900
              ? 4
              : effectiveWidth >= 520
                  ? 3
                  : effectiveWidth >= 260
                      ? 2
                      : 1;
          // Natural row heights keep labels intact at large text sizes, without
          // adding nested scrolling or fixed-aspect-ratio button tiles.
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(ArcColors.buttonRadius),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final child in children)
                    SizedBox(
                      width: (constraints.maxWidth - 8 - 4 * (columns - 1)) /
                          columns,
                      child: child,
                    ),
                ],
              ),
            ),
          );
        },
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.action,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.tooltip,
    this.selected,
    this.enabled = true,
  });

  final ReaderAction action;
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool? selected;
  final bool enabled;
  final ValueChanged<ReaderAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onSurface;
    final active = selected == true && enabled;
    return Tooltip(
      message: tooltip ?? label,
      excludeFromSemantics: true,
      child: TextButton(
        key: ValueKey(action),
        onPressed: enabled ? () => onSelected(action) : null,
        style: TextButton.styleFrom(
          foregroundColor: active ? colors.primary : foreground,
          backgroundColor: active
              ? colors.primary.withValues(alpha: 0.10)
              : colors.surfaceContainerLow,
          disabledForegroundColor: foreground.withValues(alpha: 0.38),
          minimumSize: const Size(
            ArcColors.minTouchTarget,
            ArcColors.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          animationDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        child: Semantics(
          selected: selected,
          tooltip: tooltip,
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingToggle extends StatelessWidget {
  const _ReadingToggle({
    required this.action,
    required this.icon,
    required this.label,
    required this.value,
    required this.onSelected,
    this.enabled = true,
  });

  final ReaderAction action;
  final IconData icon;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<ReaderAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onSurface;
    return Tooltip(
      message: '$label: ${value ? 'On' : 'Off'}',
      child: SwitchListTile(
        key: ValueKey(action),
        value: value,
        onChanged: enabled ? (_) => onSelected(action) : null,
        dense: false,
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        secondary: Icon(
          icon,
          size: 20,
          color: colors.onSurfaceVariant.withValues(alpha: enabled ? 1 : 0.38),
        ),
        title: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground.withValues(alpha: enabled ? 1 : 0.38),
              ),
        ),
        activeThumbColor: colors.onPrimary,
        activeTrackColor: colors.primary,
        inactiveThumbColor: colors.onSurfaceVariant,
        inactiveTrackColor: colors.surfaceContainerHighest,
      ),
    );
  }
}
