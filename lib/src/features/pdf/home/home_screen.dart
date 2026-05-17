import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../settings/settings_controller.dart';
import '../application/pdf_library_controller.dart';
import '../domain/pdf_file_item.dart';
import '../viewer/pdf_viewer_screen.dart';
import 'permission_screen.dart';
import 'widgets/pdf_card.dart';
import 'widgets/pdf_grid_card.dart';
import 'widgets/pdf_card_shimmer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  bool _searchActive = false;
  final _scrollController = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 300 && !_showScrollToTop) {
        setState(() => _showScrollToTop = true);
      } else if (_scrollController.offset <= 300 && _showScrollToTop) {
        setState(() => _showScrollToTop = false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);

    final loading =
        ref.watch(pdfLibraryControllerProvider.select((s) => s.loading));
    final permissionStatus = ref
        .watch(pdfLibraryControllerProvider.select((s) => s.permissionStatus));
    final query =
        ref.watch(pdfLibraryControllerProvider.select((s) => s.query));
    final filter =
        ref.watch(pdfLibraryControllerProvider.select((s) => s.filter));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.items));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.sortField));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.sortDirection));

    // Permission gate
    if (!loading && permissionStatus != StoragePermissionStatus.granted) {
      return Scaffold(
        appBar: AppBar(title: const Text('ArcPDF')),
        body: PermissionScreen(status: permissionStatus),
      );
    }

    final items = ctrl.filteredItems();
    final useGrid = ref.watch(settingsControllerProvider).useGrid;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: _showScrollToTop
          ? FloatingActionButton(
              onPressed: () {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.fastOutSlowIn,
                );
              },
              child: const Icon(Icons.arrow_upward_rounded),
            )
          : null,
      body: CustomScrollView(
      controller: _scrollController,
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: ctrl.refresh,
        ),
        // Unified app bar (no large duplication)
        SliverAppBar(
          floating: true,
          pinned: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ArcPDF',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              Text(
                'Your local PDF workspace',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(HugeIcons.strokeRoundedMoreVerticalCircle01),
              tooltip: 'Menu',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              elevation: 8,
              offset: const Offset(0, 48),
              onSelected: (value) {
                switch (value) {
                  case 'refresh':
                    ctrl.refresh();
                    break;
                  case 'toggle_view':
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setGrid(!useGrid);
                    break;
                  case 'sort_name':
                    ctrl.setSortField(PdfSortField.name);
                    break;
                  case 'sort_date':
                    ctrl.setSortField(PdfSortField.date);
                    break;
                  case 'sort_size':
                    ctrl.setSortField(PdfSortField.size);
                    break;
                  case 'sort_asc':
                    ctrl.setSortDirection(PdfSortDirection.ascending);
                    break;
                  case 'sort_desc':
                    ctrl.setSortDirection(PdfSortDirection.descending);
                    break;
                }
              },
              itemBuilder: (context) {
                final state = ref.read(pdfLibraryControllerProvider);
                return [
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(HugeIcons.strokeRoundedRefresh),
                        SizedBox(width: 12),
                        Text('Refresh'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_view',
                    child: Row(
                      children: [
                        Icon(useGrid
                            ? HugeIcons.strokeRoundedListView
                            : HugeIcons.strokeRoundedGridView),
                        const SizedBox(width: 12),
                        Text(useGrid ? 'List View' : 'Grid View'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('Sort By',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  CheckedPopupMenuItem(
                    value: 'sort_name',
                    checked: state.sortField == PdfSortField.name,
                    child: const Text('Name'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'sort_date',
                    checked: state.sortField == PdfSortField.date,
                    child: const Text('Date Modified'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'sort_size',
                    checked: state.sortField == PdfSortField.size,
                    child: const Text('Size'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('Order',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  CheckedPopupMenuItem(
                    value: 'sort_asc',
                    checked: state.sortDirection == PdfSortDirection.ascending,
                    child: const Text('Ascending'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'sort_desc',
                    checked: state.sortDirection == PdfSortDirection.descending,
                    child: const Text('Descending'),
                  ),
                ];
              },
            ),
          ],
        ),

        // Search + filter chips
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Animated search bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: TextField(
                    controller: _searchController,
                    onChanged: ctrl.setQuery,
                    onTap: () => setState(() => _searchActive = true),
                    onTapOutside: (_) => setState(() => _searchActive = false),
                    decoration: InputDecoration(
                      hintText: 'Search PDFs…',
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHigh,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        child: Icon(Icons.search_rounded,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      suffixIcon: _searchActive &&
                              _searchController.text.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  ctrl.setQuery('');
                                  setState(() {});
                                },
                              ),
                            )
                          : null,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 260.ms)
                    .slideY(begin: -0.1, curve: Curves.easeOutCubic),

                const SizedBox(height: 12),

                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: PdfFilter.values.map((f) {
                      final selected = filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AnimatedScale(
                          scale: selected ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          child: FilterChip(
                            selected: selected,
                            onSelected: (_) => ctrl.setFilter(f),
                            label: Text(_label(f)),
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            showCheckmark: false,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ).animate().fadeIn(delay: 80.ms, duration: 280.ms),
              ],
            ),
          ),
        ),

        // Content
        if (loading)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: 8,
              itemBuilder: (_, __) => const PdfCardShimmer(),
            ),
          )
        else if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: ArcEmptyState(
              icon: Icons.insert_drive_file_outlined,
              title: query.isNotEmpty ? 'No results found' : 'No PDFs yet',
              subtitle: query.isNotEmpty
                  ? 'Try a different search term or filter.'
                  : 'No PDFs found. Add a PDF to start reading',
            ),
          )
        else if (filter == PdfFilter.folders)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                ...ctrl.groupedByFolder().entries.map((e) {
                  final folderName = e.key;
                  final folderItems = e.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: Text(
                          folderName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...folderItems.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: useGrid
                              ? _buildGridItem(context, ref, item, index,
                                  key: ValueKey('grid_${item.path}'))
                              : _buildListItem(context, ref, item, index,
                                  key: ValueKey('list_${item.path}')),
                        );
                      }),
                    ],
                  );
                })
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: useGrid
                  ? (MediaQuery.sizeOf(context).width > 700 ? 3 : 2)
                  : 1,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              itemBuilder: (context, index) {
                final item = items[index];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: useGrid
                      ? _buildGridItem(context, ref, item, index,
                          key: ValueKey('grid_${item.path}'))
                      : _buildListItem(context, ref, item, index,
                          key: ValueKey('list_${item.path}')),
                );
              },
              childCount: items.length,
            ),
          ),

        const SliverSafeArea(
          minimum: EdgeInsets.only(bottom: 120),
          sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
      ],
    );
  }

  String _label(PdfFilter f) => switch (f) {
        PdfFilter.all => 'All',
        PdfFilter.recent => 'Recent',
        PdfFilter.downloads => 'Downloads',
        PdfFilter.large => 'Large Files',
        PdfFilter.folders => 'Folders',
      };

  Widget _buildListItem(
      BuildContext context, WidgetRef ref, PdfFileItem item, int index,
      {Key? key}) {
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    return PdfCard(
      key: key,
      item: item,
      index: index,
      onFavorite: () => ctrl.toggleFavorite(item),
      onTap: () async {
        if (item.sizeBytes == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Cannot open empty or corrupted file')),
          );
          return;
        }
        await ctrl.markRecent(item);
        if (!context.mounted) return;
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PdfViewerScreen(item: item)));
      },
    );
  }

  Widget _buildGridItem(
      BuildContext context, WidgetRef ref, PdfFileItem item, int index,
      {Key? key}) {
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    return PdfGridCard(
      key: key,
      item: item,
      index: index,
      onFavorite: () => ctrl.toggleFavorite(item),
      onTap: () async {
        if (item.sizeBytes == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Cannot open empty or corrupted file')),
          );
          return;
        }
        await ctrl.markRecent(item);
        if (!context.mounted) return;
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PdfViewerScreen(item: item)));
      },
    );
  }
}
