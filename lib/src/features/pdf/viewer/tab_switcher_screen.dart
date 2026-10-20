import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../shared/theme/arc_colors.dart';
import '../application/open_tabs_provider.dart';
import '../home/widgets/pdf_thumbnail.dart';

class TabSwitcherScreen extends ConsumerWidget {
  const TabSwitcherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsState = ref.watch(openTabsProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      height: 1.35,
      color: colors.onSurface,
    );
    final indicesByPath = {
      for (var index = 0; index < tabsState.tabs.length; index++)
        tabsState.tabs[index].path: index,
    };

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        title: Text('Open tabs',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        centerTitle: false,
        leading: IconButton(
          tooltip: 'Close tab switcher',
          icon: const Icon(HugeIcons.strokeRoundedCancel01),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: ArcColors.screenPadding),
            child: Semantics(
              label: '${tabsState.tabs.length} open documents',
              child: ExcludeSemantics(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(ArcColors.pillRadius),
                  ),
                  child: Text('${tabsState.tabs.length}',
                      style: theme.textTheme.labelLarge),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: tabsState.tabs.isEmpty
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(ArcColors.space24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(HugeIcons.strokeRoundedPdf02,
                        size: 40, color: colors.onSurfaceVariant),
                    const SizedBox(height: ArcColors.space16),
                    Text('No open tabs', style: theme.textTheme.titleMedium),
                    const SizedBox(height: ArcColors.space8),
                    Text('Open a PDF from your library to start reading.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: ArcColors.space24),
                    FilledButton(
                        onPressed: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                        child: const Text('Go Home')),
                  ]),
                ),
              )
            : LayoutBuilder(builder: (context, constraints) {
                const spacing = ArcColors.space12;
                final availableWidth = math.max(
                    0.0, constraints.maxWidth - ArcColors.screenPadding * 2);
                final scaler = MediaQuery.textScalerOf(context);
                final scale = scaler.scale(14) / 14;
                final columns = ((availableWidth + spacing) /
                        (128 * scale.clamp(1.0, 1.8) + spacing))
                    .floor()
                    .clamp(1, 6);
                final cardWidth =
                    (availableWidth - spacing * (columns - 1)) / columns;
                // Paragraph line boxes round up to logical pixels; match that
                // rounding so scaled text cannot overflow the footer.
                final footerHeight =
                    (scaler.scale(14) * 1.35).ceilToDouble() * 2 +
                        (scaler.scale(11) * 1.4).ceilToDouble() +
                        28;

                Widget grid = GridView.builder(
                  padding: const EdgeInsets.all(ArcColors.screenPadding),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    mainAxisExtent: cardWidth * 0.95 + 48 + footerHeight,
                  ),
                  itemCount: tabsState.tabs.length,
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indicesByPath[key.value] : null,
                  itemBuilder: (context, index) {
                    final item = tabsState.tabs[index];
                    final isActive = index == tabsState.activeIndex;
                    final radius = BorderRadius.circular(ArcColors.cardRadius);

                    void selectTab() {
                      final currentIndex = ref
                          .read(openTabsProvider)
                          .tabs
                          .indexWhere((tab) => tab.path == item.path);
                      if (currentIndex < 0) return;
                      ref
                          .read(openTabsProvider.notifier)
                          .setActiveIndex(currentIndex);
                      Navigator.of(context).pop();
                    }

                    return Material(
                      key: ValueKey(item.path),
                      color: colors.surfaceContainerLow,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: radius,
                        side: BorderSide(
                          color:
                              isActive ? colors.primary : colors.outlineVariant,
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Semantics(
                              container: true,
                              button: true,
                              selected: isActive,
                              label: 'Switch to ${item.name}',
                              child: InkWell(
                                onTap: selectTab,
                                borderRadius: radius,
                                focusColor:
                                    colors.primary.withValues(alpha: 0.16),
                                hoverColor:
                                    colors.primary.withValues(alpha: 0.08),
                                child: ExcludeSemantics(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        height: 48,
                                        child: Align(
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16),
                                            child: Icon(
                                              isActive
                                                  ? Icons.check_circle_rounded
                                                  : Icons.tab_outlined,
                                              size: 20,
                                              color: isActive
                                                  ? colors.primary
                                                  : colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: PdfThumbnail(
                                              path: item.path,
                                              isEncrypted: item.isEncrypted,
                                              isCorrupted: item.isCorrupted,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        height: footerHeight,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                item.name.replaceAll(
                                                    RegExp(r'\.pdf$',
                                                        caseSensitive: false),
                                                    ''),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: titleStyle,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                isActive
                                                    ? 'Reading now'
                                                    : 'PDF document',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  fontSize: 11,
                                                  height: 1.4,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            top: 0,
                            end: 0,
                            child: IconButton(
                              tooltip: 'Close ${item.name}',
                              constraints: const BoxConstraints(
                                minWidth: ArcColors.minTouchTarget,
                                minHeight: ArcColors.minTouchTarget,
                              ),
                              color: colors.onSurfaceVariant,
                              icon: Icon(HugeIcons.strokeRoundedCancel01,
                                  semanticLabel: 'Close ${item.name}',
                                  size: 18),
                              onPressed: () {
                                final currentTabs =
                                    ref.read(openTabsProvider).tabs;
                                final currentIndex = currentTabs
                                    .indexWhere((tab) => tab.path == item.path);
                                if (currentIndex < 0) return;
                                ref
                                    .read(openTabsProvider.notifier)
                                    .closeTab(currentIndex);
                                if (ref.read(openTabsProvider).tabs.isEmpty) {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
                // One short entrance effect, not a ticker for every preview.
                if (!reduceMotion) {
                  grid = grid.animate().fadeIn(duration: 160.ms);
                }
                return grid;
              }),
      ),
    );
  }
}
