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
    final primary = ArcColors.primary(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 14,
      color: ArcColors.onSurface(context),
    );
    final indicesByPath = {
      for (var index = 0; index < tabsState.tabs.length; index++)
        tabsState.tabs[index].path: index,
    };

    return Scaffold(
      backgroundColor: ArcColors.surface(context),
      appBar: AppBar(
        backgroundColor: ArcColors.surface(context),
        foregroundColor: ArcColors.onSurface(context),
        title: const Text('Open Tabs',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Close tab switcher',
          icon: const Icon(HugeIcons.strokeRoundedCancel01,
              semanticLabel: 'Close tab switcher'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: tabsState.tabs.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('No open tabs'),
                const SizedBox(height: ArcColors.space16),
                FilledButton(
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                    child: const Text('Go Home'))
              ]))
            : LayoutBuilder(builder: (context, constraints) {
                const spacing = ArcColors.space16;
                final availableWidth = math.max(
                    0.0, constraints.maxWidth - ArcColors.screenPadding * 2);
                final columns = math.max(
                    1, ((availableWidth + spacing) / (220 + spacing)).floor());
                final cardWidth =
                    (availableWidth - spacing * (columns - 1)) / columns;
                final headerHeight = math.max(
                    64.0,
                    MediaQuery.textScalerOf(context).scale(14) *
                            (titleStyle?.height ?? 1.5) *
                            2 +
                        ArcColors.space16);

                return GridView.builder(
                  padding: const EdgeInsets.all(ArcColors.screenPadding),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    mainAxisExtent: cardWidth * 1.1 + headerHeight,
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

                    Widget card = Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: radius,
                        side: BorderSide(
                          color:
                              isActive ? primary : ArcColors.outline(context),
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
                                focusColor: primary.withValues(alpha: 0.16),
                                hoverColor: primary.withValues(alpha: 0.08),
                                child: ExcludeSemantics(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        height: headerHeight,
                                        padding: const EdgeInsets.fromLTRB(
                                            ArcColors.space16,
                                            ArcColors.space8,
                                            ArcColors.space4,
                                            ArcColors.space8),
                                        color: isActive
                                            ? primary.withValues(alpha: 0.06)
                                            : null,
                                        child: Row(
                                          children: [
                                            if (isActive) ...[
                                              Icon(Icons.check_circle_outline,
                                                  size: 20, color: primary),
                                              const SizedBox(
                                                  width: ArcColors.space8),
                                            ],
                                            Expanded(
                                              child: Text(
                                                item.name.replaceAll(
                                                    RegExp(r'\.pdf$',
                                                        caseSensitive: false),
                                                    ''),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: titleStyle,
                                              ),
                                            ),
                                            const SizedBox(
                                                width:
                                                    ArcColors.minTouchTarget),
                                          ],
                                        ),
                                      ),
                                      Divider(
                                          height: 1,
                                          color: ArcColors.outlineVariant(
                                              context)),
                                      Expanded(
                                        child: PdfThumbnail(
                                          path: item.path,
                                          isEncrypted: item.isEncrypted,
                                          isCorrupted: item.isCorrupted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: ArcColors.space8,
                            right: ArcColors.space4,
                            child: IconButton(
                              tooltip: 'Close ${item.name}',
                              constraints: const BoxConstraints(
                                minWidth: ArcColors.minTouchTarget,
                                minHeight: ArcColors.minTouchTarget,
                              ),
                              color: ArcColors.onSurfaceVariant(context),
                              icon: Icon(HugeIcons.strokeRoundedCancel01,
                                  size: 20,
                                  semanticLabel: 'Close ${item.name}'),
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

                    if (!reduceMotion) {
                      card = card.animate().fadeIn(duration: 200.ms);
                    }
                    return KeyedSubtree(key: ValueKey(item.path), child: card);
                  },
                );
              }),
      ),
    );
  }
}
