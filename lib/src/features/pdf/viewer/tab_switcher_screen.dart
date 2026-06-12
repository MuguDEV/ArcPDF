import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../application/open_tabs_provider.dart';
import '../home/widgets/pdf_thumbnail.dart';

class TabSwitcherScreen extends ConsumerWidget {
  const TabSwitcherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsState = ref.watch(openTabsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Tabs', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(HugeIcons.strokeRoundedCancel01),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: tabsState.tabs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   const Text('No open tabs'),
                   const SizedBox(height: 16),
                   FilledButton(
                     onPressed: () {
                        // Pop back to home (assuming MultiTab is the only route stacked)
                        Navigator.of(context).popUntil((route) => route.isFirst);
                     },
                     child: const Text('Go Home')
                   )
                ]
              )
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: MasonryGridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                itemCount: tabsState.tabs.length,
                itemBuilder: (context, index) {
                  final item = tabsState.tabs[index];
                  final isActive = index == tabsState.activeIndex;

                  return GestureDetector(
                    onTap: () {
                      ref.read(openTabsProvider.notifier).setActiveIndex(index);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header with close button
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    ref.read(openTabsProvider.notifier).closeTab(index);
                                    if (ref.read(openTabsProvider).tabs.isEmpty) {
                                      // If we close the last tab from the grid, pop everything and return home.
                                      Navigator.of(context).popUntil((route) => route.isFirst);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(
                                      HugeIcons.strokeRoundedCancel01,
                                      size: 18,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Thumbnail
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
                            child: AspectRatio(
                              aspectRatio: 1 / 1.4,
                              child: PdfThumbnail(
                                path: item.path,
                                isEncrypted: item.isEncrypted,
                                isCorrupted: item.isCorrupted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
