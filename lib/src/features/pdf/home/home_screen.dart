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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    
    final loading = ref.watch(pdfLibraryControllerProvider.select((s) => s.loading));
    final permissionStatus = ref.watch(pdfLibraryControllerProvider.select((s) => s.permissionStatus));
    final query = ref.watch(pdfLibraryControllerProvider.select((s) => s.query));
    final filter = ref.watch(pdfLibraryControllerProvider.select((s) => s.filter));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.items));

    // Permission gate
    if (!loading && permissionStatus != StoragePermissionStatus.granted) {
      return Scaffold(
        appBar: AppBar(title: const Text('ArcPDF')),
        body: PermissionScreen(status: permissionStatus),
      );
    }

    final items = ctrl.filteredItems();
    final useGrid = ref.watch(settingsControllerProvider).useGrid;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
                const Text('ArcPDF', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  'Your local PDF workspace',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: ctrl.refresh,
                icon: const Icon(HugeIcons.strokeRoundedRefresh),
                tooltip: 'Refresh',
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
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 8, right: 4),
                          child: Icon(Icons.search_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        suffixIcon: _searchActive && _searchController.text.isNotEmpty
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
                  ).animate().fadeIn(duration: 260.ms).slideY(begin: -0.1, curve: Curves.easeOutCubic),

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
                    : 'Add PDF files to your device storage, then pull to refresh.',
              ),
            )
          else
            useGrid
                ? SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      itemBuilder: (context, index) => _buildGridItem(context, ref, items[index], index),
                      childCount: items.length,
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) => _buildListItem(context, ref, items[index], index),
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
      };

  Widget _buildListItem(BuildContext context, WidgetRef ref, PdfFileItem item, int index) {
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    return PdfCard(
      item: item,
      index: index,
      onFavorite: () => ctrl.toggleFavorite(item),
      onTap: () async {
        if (item.sizeBytes == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot open empty or corrupted file')),
          );
          return;
        }
        await ctrl.markRecent(item);
        if (!context.mounted) return;
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => PdfViewerScreen(item: item)));
      },
    );
  }

  Widget _buildGridItem(BuildContext context, WidgetRef ref, PdfFileItem item, int index) {
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    return PdfGridCard(
      item: item,
      index: index,
      onFavorite: () => ctrl.toggleFavorite(item),
      onTap: () async {
        if (item.sizeBytes == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot open empty or corrupted file')),
          );
          return;
        }
        await ctrl.markRecent(item);
        if (!context.mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerScreen(item: item)));
      },
    );
  }
}
