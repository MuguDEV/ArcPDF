import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/empty_state.dart';
import '../application/pdf_library_controller.dart';
import '../domain/pdf_file_item.dart';
import '../viewer/pdf_viewer_screen.dart';

class RecentScreen extends ConsumerWidget {
  const RecentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(pdfLibraryControllerProvider.select((s) => s.loading));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.items));
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    final groups = ctrl.groupedRecents();
    final isEmpty = groups.isEmpty;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: ctrl.refresh,
        ),
        SliverAppBar(
            floating: true,
            pinned: true,
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
              child: Center(child: CircularProgressIndicator.adaptive()),
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
            _RecentGroupsList(groups: groups, ctrl: ctrl),

          const SliverSafeArea(
            minimum: EdgeInsets.only(bottom: 120),
            sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
        ],
      );
  }
}

class _RecentGroupsList extends ConsumerWidget {
  const _RecentGroupsList({required this.groups, required this.ctrl});
  final Map<String, List<PdfFileItem>> groups;
  final PdfLibraryController ctrl;

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
              return _RecentTile(
                item: item,
                index: idx,
                onTap: () async {
                  await ctrl.markRecent(item);
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PdfViewerScreen(item: item)),
                  );
                },
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

class _RecentTile extends StatefulWidget {
  const _RecentTile({required this.item, required this.index, required this.onTap});
  final PdfFileItem item;
  final int index;
  final VoidCallback onTap;

  @override
  State<_RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends State<_RecentTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openedAt = widget.item.openedAt;
    final timeStr = openedAt != null ? DateFormat.jm().format(openedAt) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    HugeIcons.strokeRoundedPdf02,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fileSize(widget.item.sizeBytes),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate(delay: (widget.index * 30).ms)
        .fadeIn(duration: 280.ms)
        .slideX(begin: 0.04, curve: Curves.easeOutCubic);
  }

  String _fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
