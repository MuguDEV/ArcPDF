import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
          : GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.65, // Standard Chrome-like tall card
              ),
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
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isActive ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header with close button
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          decoration: BoxDecoration(
                            color: isActive ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : Colors.transparent,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  ref.read(openTabsProvider.notifier).closeTab(index);
                                  if (ref.read(openTabsProvider).tabs.isEmpty) {
                                    Navigator.of(context).popUntil((route) => route.isFirst);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    HugeIcons.strokeRoundedCancel01,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Divider
                        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        // Thumbnail Body
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(23)),
                            child: PdfThumbnail(
                              path: item.path,
                              isEncrypted: item.isEncrypted,
                              isCorrupted: item.isCorrupted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().scale(
                        duration: 300.ms,
                        curve: Curves.easeOutBack,
                        begin: const Offset(0.8, 0.8),
                        delay: (index * 50).ms,
                      ).fadeIn(duration: 200.ms),
                );
              },
            ),
    );
  }
}
