import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../shared/widgets/empty_state.dart';
import '../application/pdf_library_controller.dart';
import '../../vault/vault_controller.dart';
import '../home/widgets/pdf_card_shimmer.dart';

import '../viewer/pdf_viewer_screen.dart';
import '../home/widgets/pdf_custom_card.dart';
import '../../../shared/widgets/glass_app_bar.dart';

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
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            await ctrl.refresh();
          },
        ),
        const GlassSliverAppBar(
            title: Text('Favorites', style: TextStyle(fontWeight: FontWeight.w700)),
          ),

          if (lib.loading)
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.builder(
                itemCount: 6,
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
                iconColor: Colors.grey.shade400,
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
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: PdfCustomCard(
                      item: item,
                      index: index,
                      onFavorite: () => ref.read(pdfLibraryControllerProvider.notifier).toggleFavorite(item),
                      onVault: () async {
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
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PdfViewerScreen(item: item)),
                        );
                      },
                    ).animate(key: ValueKey('fav_${item.path}'))
                     .fadeIn(
                       duration: 400.ms,
                       delay: (index > 20 ? 0 : index * 30).ms,
                     )
                     .slideY(
                       begin: 0.1,
                       duration: 400.ms,
                       delay: (index > 20 ? 0 : index * 30).ms,
                       curve: Curves.easeInOutCubicEmphasized,
                     ),
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
