import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../shared/widgets/empty_state.dart';
import '../application/pdf_library_controller.dart';
import '../home/widgets/pdf_card_shimmer.dart';
import '../viewer/pdf_viewer_screen.dart';
import 'favorite_grid_card.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(pdfLibraryControllerProvider);
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    final items = ctrl.filteredItems(favoritesOnly: true);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: ctrl.refresh,
        ),
        const SliverAppBar(
            floating: true,
            pinned: true,
            title: Text('Favorites', style: TextStyle(fontWeight: FontWeight.w700)),
          ),

          if (lib.loading)
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childCount: 6,
                itemBuilder: (_, __) => const PdfCardShimmer(),
              ),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ArcEmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'No favorites yet',
                subtitle: 'Long-press any PDF in the Home tab to add it to your favorites.',
                iconColor: Colors.pink.shade300,
                animated: true,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '${items.length} saved PDF${items.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ).animate().fadeIn(duration: 300.ms),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return FavoriteGridCard(
                    item: item,
                    index: index,
                    onTap: () async {
                      await ctrl.markRecent(item);
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PdfViewerScreen(item: item)),
                      );
                    },
                    onUnfavorite: () => ctrl.toggleFavorite(item),
                  );
                },
              ),
            ),
          ],

          const SliverSafeArea(
            minimum: EdgeInsets.only(bottom: 120),
            sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
        ],
      );
  }
}
