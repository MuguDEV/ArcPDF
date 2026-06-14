import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/empty_state.dart';
import '../application/pdf_library_controller.dart';
import '../application/open_tabs_provider.dart';
import '../../vault/vault_controller.dart';
import '../../security/security_controller.dart';
import '../domain/pdf_file_item.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../viewer/multi_tab_viewer_screen.dart';
import '../home/widgets/pdf_custom_card.dart';
import '../../../shared/widgets/glass_app_bar.dart';
import '../../../shared/widgets/arc_progress_indicator.dart';

class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key});

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(pdfLibraryControllerProvider.select((s) => s.loading));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.items));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.recents));
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    final groups = ctrl.groupedRecents();
    final isEmpty = groups.isEmpty;

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 500, // Optimize cache extent for smoother scroll memory allocation
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            await ctrl.refresh();
          },
        ),
        GlassSliverAppBar(
            title: const Text('Recent', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              if (!isEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Clear Recent History'),
                        content: const Text('Are you sure you want to clear your recent history? This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ctrl.clearRecents();
                    }
                  },
                ),
            ],
          ),

          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: ArcProgressIndicator()),
            )
          else if (isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: ArcEmptyState(
                icon: Icons.history_rounded,
                title: 'Nothing opened yet',
                subtitle: 'Files you open will appear here, grouped by when you last read them.',
                animated: true,
              ),
            )
          else
            _RecentGroupsList(groups: groups, ctrl: ctrl, scrollController: _scrollController),

          const SliverSafeArea(
            minimum: EdgeInsets.only(bottom: 140),
            sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
        ],
      );
  }
}

class _RecentGroupsList extends ConsumerWidget {
  const _RecentGroupsList({required this.groups, required this.ctrl, this.scrollController});
  final Map<String, List<PdfFileItem>> groups;
  final PdfLibraryController ctrl;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final slivers = <Widget>[];
    var itemIndex = 0;

    for (final entry in groups.entries) {
      final label = entry.key;
      final items = entry.value;

      // Section header
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 280.ms),
          ),
        ),
      );

      // Items in this group
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final idx = itemIndex + i;
              final item = items[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: PdfCustomCard(
                  item: item,
                  index: idx,
                  scrollController: scrollController,
                  onFavorite: () => ref.read(pdfLibraryControllerProvider.notifier).toggleFavorite(item),
                  onVault: () async {
                    final security = ref.read(securityControllerProvider);
                    if (!security.isLockEnabled) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('App lock is not enabled. Enable it in Settings first.'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    final success = await ref.read(vaultControllerProvider.notifier).moveToVault(item);
                    if (success && context.mounted) {
                      ref.read(pdfLibraryControllerProvider.notifier).refresh();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Moved to Vault'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  onTap: () async {
                    await ctrl.markRecent(item);
                    if (!context.mounted) return;
                    ref.read(openTabsProvider.notifier).openTab(item);
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MultiTabViewerScreen()),
                    );
                  },
                )
                .animate()
                .fadeIn(
                  delay: (idx > 20 ? 0 : idx * 30).ms,
                  duration: 400.ms,
                )
                .slideY(
                  begin: 0.1,
                  delay: (idx > 20 ? 0 : idx * 30).ms,
                  duration: 400.ms,
                  curve: Curves.easeInOutCubicEmphasized,
                ),
              );
            },
          ),
        ),
      );

      itemIndex += items.length;
    }

    return SliverMainAxisGroup(slivers: slivers);
  }
}
