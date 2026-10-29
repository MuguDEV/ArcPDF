import 'dart:io';

import 'package:flutter/material.dart';
import '../application/pdf_error_handler.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';

import 'package:install_plugin/install_plugin.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/theme/arc_colors.dart';
import '../../settings/haptic_service.dart';
import 'dart:async';
import '../application/pdf_library_controller.dart';
import '../application/open_tabs_provider.dart';
import '../../vault/vault_controller.dart';
import '../viewer/multi_tab_viewer_screen.dart';
import '../../security/security_controller.dart';
import '../domain/pdf_file_item.dart';
import 'permission_screen.dart';
import '../../tools/pages/merge_pdfs_page.dart';
import 'widgets/pdf_custom_card.dart';
import 'widgets/pdf_card_shimmer.dart';
import '../../vault/vault_screen.dart';
import '../../../shared/widgets/glass_app_bar.dart';
import '../../../shared/widgets/dynamic_island_notification.dart';
import '../../../shared/utils/glass_bottom_sheet.dart';
import '../../../shared/widgets/sheet/app_components.dart';
import '../../../shared/widgets/animated_mesh_background.dart';
import '../../updater/updater_service.dart';
import '../../settings/settings_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();

  final _scrollController = ScrollController();
  bool _showScrollToTop = false;
  Timer? _debounceTimer;

  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};
  bool _bulkBusy = false;

  GitHubRelease? _availableUpdate;
  bool _isDownloadingUpdate = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkBackgroundUpdate();
    });
  }

  Future<void> _checkBackgroundUpdate() async {
    if (!mounted) return;
    final release = await UpdaterService.checkForUpdates(
      client: ref.read(updaterHttpClientProvider),
    );
    if (release != null && mounted) {
      final settings = ref.read(settingsControllerProvider);
      if (settings.skippedUpdateVersion != release.version) {
        setState(() {
          _availableUpdate = release;
        });
      }
    }
  }

  Future<void> _downloadAndInstallUpdate() async {
    final release = _availableUpdate;
    if (!mounted || release == null || _isDownloadingUpdate) return;
    if (!Platform.isAndroid) {
      DynamicIslandNotification.show(context,
          'APK installation is Android-only. Download from Settings instead.',
          icon: HugeIcons.strokeRoundedAlert01);
      return;
    }
    final client = ref.read(updaterHttpClientProvider);
    setState(() => _isDownloadingUpdate = true);
    DynamicIslandNotification.show(context, 'Downloading update...',
        icon: HugeIcons.strokeRoundedCloudDownload);
    try {
      final file = await UpdaterService.downloadUpdate(release, client: client);
      if (!mounted || _availableUpdate?.version != release.version) return;
      // Never open an installer after leaving the page or backgrounding the app.
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if ((lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          ModalRoute.of(context)?.isCurrent == false ||
          !TickerMode.valuesOf(context).enabled) {
        return;
      }
      DynamicIslandNotification.show(
          context, 'Update downloaded! Opening installer...',
          icon: HugeIcons.strokeRoundedCheckmarkBadge01);
      final result = await InstallPlugin.install(file.path);
      if (result is Map && result['isSuccess'] == false) {
        throw StateError('Installer could not be opened');
      }
      if (mounted) setState(() => _availableUpdate = null);
    } catch (_) {
      if (mounted) {
        DynamicIslandNotification.show(
            context, 'Could not download or open the update. Please try again.',
            icon: HugeIcons.strokeRoundedAlert01);
      }
    } finally {
      if (mounted) setState(() => _isDownloadingUpdate = false);
    }
  }

  void _ignoreUpdate() {
    if (_availableUpdate != null) {
      ref
          .read(settingsControllerProvider.notifier)
          .setSkippedUpdateVersion(_availableUpdate!.version);
      setState(() {
        _availableUpdate = null;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
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
    final libraryItems =
        ref.watch(pdfLibraryControllerProvider.select((s) => s.items));
    final favorites =
        ref.watch(pdfLibraryControllerProvider.select((s) => s.favorites));
    // A refresh, rename, or vault move must not leave actionable stale paths.
    if (_selectedPaths.isNotEmpty) {
      _selectedPaths.retainAll(libraryItems.map((item) => item.path));
    }
    ref.watch(pdfLibraryControllerProvider.select((s) => s.tags));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.sortField));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.sortDirection));
    final selectedTag =
        ref.watch(pdfLibraryControllerProvider.select((s) => s.selectedTag));

    // Permission gate
    if (!loading && permissionStatus != StoragePermissionStatus.granted) {
      return Scaffold(
        appBar: AppBar(title: const Text('ArcPDF')),
        body: PermissionScreen(status: permissionStatus),
      );
    }

    final items = ctrl.filteredItems();
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);

    final reduceMotion =
        settings.lowPowerMode || MediaQuery.disableAnimationsOf(context);
    final selectedItems = _isSelectionMode
        ? libraryItems
            .where((item) => _selectedPaths.contains(item.path))
            .toList()
        : const <PdfFileItem>[];
    final tags = ctrl.getAllTags();

    final scaffold = Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: _isSelectionMode
          ? PreferredSize(
              preferredSize: const Size.fromHeight(72),
              child: SafeArea(
                bottom: false,
                child: _buildBulkActions(items, selectedItems, favorites,
                    reduceMotion: reduceMotion),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: !_isSelectionMode && _showScrollToTop
          ? FloatingActionButton(
              tooltip: 'Scroll to top',
              onPressed: () {
                if (reduceMotion) {
                  _scrollController.jumpTo(0);
                  return;
                }
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.fastOutSlowIn,
                );
              },
              backgroundColor: theme.colorScheme.secondaryContainer,
              foregroundColor: theme.colorScheme.onSecondaryContainer,
              elevation: 4,
              child: const Icon(Icons.arrow_upward_rounded),
            )
          : null,
      body: Stack(
        children: [
          if (settings.enableMeshBackground && !reduceMotion)
            const Positioned.fill(child: AnimatedMeshBackground()),
          SafeArea(
            top: false,
            bottom: false,
            child: CustomRefreshIndicator(
              onRefresh: ctrl.refresh,
              offsetToArmed: 80,
              builder: (BuildContext context, Widget child,
                  IndicatorController controller) {
                return Stack(
                  children: [
                    child,
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (BuildContext context, Widget? _) {
                          final theme = Theme.of(context);
                          final isRefreshing = controller.isLoading;
                          final isSettling = controller.isSettling;

                          if (controller.isIdle) {
                            return const SizedBox.shrink();
                          }

                          final double value = controller.value;
                          const double containerSize = 48.0;

                          // Calculate positions and rotations
                          const double maxTopPadding = 100.0;
                          final double topPadding =
                              value * maxTopPadding - containerSize;

                          return Container(
                            padding: EdgeInsets.only(
                                top: topPadding > 0 ? topPadding : 0),
                            alignment: Alignment.center,
                            child: Container(
                              width: containerSize,
                              height: containerSize,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.shadow
                                        .withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: isRefreshing || isSettling
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          value: reduceMotion ? 0.5 : null,
                                          strokeWidth: 2.5,
                                          color: theme.colorScheme.primary,
                                        ),
                                      )
                                    : Transform.rotate(
                                        angle: reduceMotion
                                            ? 0
                                            : value * 2 * 3.14159,
                                        child: Icon(
                                          HugeIcons.strokeRoundedRefresh,
                                          color: theme.colorScheme.primary
                                              .withValues(
                                            alpha: (value * 2).clamp(0.0, 1.0),
                                          ),
                                          size: 24,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              child: CustomScrollView(
                cacheExtent: 200.0,
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  // Unified app bar (no large duplication)
                  if (_availableUpdate != null && !_isSelectionMode)
                    SliverToBoxAdapter(
                      child: Material(
                        color: theme.colorScheme.primaryContainer,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(HugeIcons.strokeRoundedPackageOpen,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Update Available: ${_availableUpdate!.version}',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: theme.colorScheme
                                                    .onPrimaryContainer),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: _ignoreUpdate,
                                  child: const Text('Ignore'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: _isDownloadingUpdate
                                      ? null
                                      : _downloadAndInstallUpdate,
                                  child: _isDownloadingUpdate
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              value: reduceMotion ? 0.5 : null,
                                              strokeWidth: 2))
                                      : const Text('Update'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Unified app bar (no large duplication)
                  if (!_isSelectionMode)
                    GlassSliverAppBar(
                      title: Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('ArcPDF',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                              'Your local PDF workspace',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.1,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon:
                              const Icon(HugeIcons.strokeRoundedFolderSecurity),
                          tooltip: 'Secure Vault',
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const VaultScreen()));
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                              HugeIcons.strokeRoundedMoreVerticalCircle01),
                          tooltip: 'Menu',
                          onPressed: () {
                            ref.read(hapticServiceProvider).lightImpact();
                            _showGlassMenu(context, ref, ctrl);
                          },
                        ),
                      ],
                    ),

                  if (!_isSelectionMode)
                    const SliverToBoxAdapter(child: _HomeResumeCard()),

                  // Search + filter chips
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _searchController,
                            onChanged: (val) {
                              if (_debounceTimer?.isActive ?? false) {
                                _debounceTimer!.cancel();
                              }
                              _debounceTimer =
                                  Timer(const Duration(milliseconds: 300), () {
                                ctrl.setQuery(val);
                              });
                            },
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: InputDecoration(
                              hintText: 'Search PDFs…',
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
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
                                padding:
                                    const EdgeInsets.only(left: 8, right: 4),
                                child: Icon(Icons.search_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                              suffixIcon:
                                  ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _searchController,
                                builder: (context, value, _) =>
                                    value.text.isEmpty
                                        ? const SizedBox.shrink()
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            icon: const Icon(
                                                Icons.clear_rounded,
                                                size: 20),
                                            onPressed: () {
                                              _debounceTimer?.cancel();
                                              _searchController.clear();
                                              ctrl.setQuery('');
                                            },
                                          ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Tags and library filters share the same sizing and shape.
                          if (tags.isNotEmpty) ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: tags.map((tag) {
                                  final isSelected = selectedTag == tag;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _HomeFilterControl(
                                      label: tag,
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        ref
                                            .read(hapticServiceProvider)
                                            .selectionClick();
                                        ctrl.setSelectedTag(
                                            selected ? tag : null);
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],

                          // Filter chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: PdfFilter.values.map((f) {
                              final selected = filter == f;
                              return _HomeFilterControl(
                                selected: selected,
                                onSelected: (_) {
                                  ref.read(hapticServiceProvider).lightImpact();
                                  ctrl.setFilter(f);
                                },
                                label: _label(f),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Keep indexed documents usable while discovery continues.
                  SliverToBoxAdapter(
                    child: loading && libraryItems.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Semantics(
                              key: const ValueKey('home-library-progress'),
                              liveRegion: true,
                              label: 'Refreshing PDF library',
                              excludeSemantics: true,
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                value: reduceMotion ? 0.5 : null,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (loading && libraryItems.isEmpty)
                    SliverPadding(
                      key: const ValueKey('home-initial-loading'),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: 8,
                        itemBuilder: (_, __) => reduceMotion
                            ? Container(
                                height: 136,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              )
                            : const PdfCardShimmer(),
                      ),
                    )
                  else if (items.isEmpty && !loading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ArcEmptyState(
                        icon: Icons.insert_drive_file_outlined,
                        title: query.isNotEmpty
                            ? 'No results found'
                            : 'No PDFs yet',
                        subtitle: query.isNotEmpty
                            ? 'Try a different search term or filter.'
                            : 'No PDFs found. Add a PDF to start reading',
                        animated: !reduceMotion,
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
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16.0),
                                  child: Text(
                                    folderName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...folderItems.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final item = entry.value;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10.0),
                                    child: _buildListItem(
                                        context, ref, item, index,
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
                      sliver: SliverList.builder(
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildListItem(context, ref, item, index,
                                key: ValueKey('list_${item.path}')),
                          );
                        },
                        itemCount: items.length,
                      ),
                    ),

                  SliverSafeArea(
                    minimum: EdgeInsets.only(
                      bottom: _isSelectionMode
                          ? 24
                          : 88 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode && !_bulkBusy) _clearSelection();
      },
      child: scaffold,
    );
  }

  void _clearSelection() {
    setState(() {
      _selectedPaths.clear();
      _isSelectionMode = false;
    });
  }

  Widget _buildBulkActions(List<PdfFileItem> visibleItems,
      List<PdfFileItem> selectedItems, Set<String> favorites,
      {required bool reduceMotion}) {
    final theme = Theme.of(context);
    final hasSelection = selectedItems.isNotEmpty && !_bulkBusy;
    final allVisibleSelected = visibleItems.isNotEmpty &&
        visibleItems.every((item) => _selectedPaths.contains(item.path));
    final allFavorites = selectedItems.isNotEmpty &&
        selectedItems.every((item) => favorites.contains(item.path));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Material(
            key: const ValueKey('home-selection-toolbar'),
            color: theme.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final showLabels = constraints.maxWidth >= 560 &&
                        MediaQuery.textScalerOf(context).scale(14) <= 20;
                    Widget action(
                        String label, IconData icon, VoidCallback? onPressed,
                        {bool emphasized = false}) {
                      final style = IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        visualDensity: VisualDensity.standard,
                        foregroundColor: emphasized
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        backgroundColor:
                            emphasized ? theme.colorScheme.primary : null,
                        disabledBackgroundColor: emphasized
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.12)
                            : null,
                      );
                      return showLabels
                          ? Tooltip(
                              message: label,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                  foregroundColor: emphasized
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                                  backgroundColor: emphasized
                                      ? theme.colorScheme.primary
                                      : null,
                                  disabledBackgroundColor: emphasized
                                      ? theme.colorScheme.onSurface
                                          .withValues(alpha: 0.12)
                                      : null,
                                ),
                                onPressed: onPressed,
                                icon: Icon(icon, size: 20),
                                label: Text(label),
                              ),
                            )
                          : IconButton(
                              style: style,
                              tooltip: label,
                              onPressed: onPressed,
                              icon: Icon(icon, size: 22),
                            );
                    }

                    return Row(
                      children: [
                        IconButton(
                          constraints:
                              const BoxConstraints(minWidth: 44, minHeight: 44),
                          tooltip: 'Exit selection',
                          onPressed: _bulkBusy ? null : _clearSelection,
                          icon: const Icon(Icons.close_rounded),
                        ),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            label: '${selectedItems.length} PDFs selected',
                            excludeSemantics: true,
                            child: Text(
                              '${selectedItems.length}',
                              key: const ValueKey('home-selection-count'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Builder(
                            builder: (context) => action(
                                  'Share',
                                  Icons.share_outlined,
                                  hasSelection
                                      ? () async {
                                          final box = context.findRenderObject()
                                              as RenderBox;
                                          await _shareSelected(
                                              selectedItems,
                                              box.localToGlobal(Offset.zero) &
                                                  box.size);
                                        }
                                      : null,
                                )),
                        action(
                          allFavorites ? 'Unfavorite' : 'Favorite',
                          allFavorites
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          hasSelection
                              ? () => _favoriteSelected(
                                  selectedItems, !allFavorites)
                              : null,
                        ),
                        action(
                          'Merge',
                          HugeIcons.strokeRoundedLayers01,
                          hasSelection && selectedItems.length > 1
                              ? () => _handleQuickCombine(context)
                              : null,
                          emphasized: true,
                        ),
                        PopupMenuButton<_HomeSelectionAction>(
                          tooltip: 'More selection actions',
                          enabled: !_bulkBusy,
                          constraints: const BoxConstraints(
                              minWidth: 220, maxWidth: 300),
                          icon: const Icon(Icons.more_horiz_rounded),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            visualDensity: VisualDensity.standard,
                          ),
                          popUpAnimationStyle:
                              reduceMotion ? AnimationStyle.noAnimation : null,
                          onSelected: (action) {
                            if (_bulkBusy) return;
                            switch (action) {
                              case _HomeSelectionAction.selectAll:
                                setState(() => _selectedPaths.addAll(
                                    visibleItems.map((item) => item.path)));
                              case _HomeSelectionAction.clear:
                                setState(_selectedPaths.clear);
                              case _HomeSelectionAction.delete:
                                final currentItems = ref
                                    .read(pdfLibraryControllerProvider)
                                    .items;
                                _deleteSelected(currentItems
                                    .where((item) =>
                                        _selectedPaths.contains(item.path))
                                    .toList());
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _HomeSelectionAction.selectAll,
                              enabled: visibleItems.isNotEmpty &&
                                  !allVisibleSelected,
                              child: const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.select_all_rounded),
                                title: Text('Select all'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _HomeSelectionAction.clear,
                              enabled: selectedItems.isNotEmpty,
                              child: const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.deselect_rounded),
                                title: Text('Clear selection'),
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: _HomeSelectionAction.delete,
                              enabled: hasSelection,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.delete_outline_rounded,
                                    color: hasSelection
                                        ? theme.colorScheme.error
                                        : null),
                                title: Text('Delete',
                                    style: TextStyle(
                                        color: hasSelection
                                            ? theme.colorScheme.error
                                            : null)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }),
                ),
                if (_bulkBusy)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 0,
                    child: Semantics(
                      liveRegion: true,
                      label: 'Working on selected PDFs',
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        value: reduceMotion ? 0.5 : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _bulkMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _shareSelected(List<PdfFileItem> items, Rect origin) async {
    if (_bulkBusy || items.isEmpty) return;
    setState(() => _bulkBusy = true);
    try {
      // Do not silently share only part of the user's selection.
      for (final item in items) {
        if (!await File(item.path).exists()) {
          throw FileSystemException(
              'Selected PDF is no longer available', item.path);
        }
      }
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: items.map((item) => XFile(item.path)).toList(),
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      _bulkMessage(
          'Could not share the selected PDFs. Check that the files are available and try again.');
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _favoriteSelected(List<PdfFileItem> items, bool favorite) async {
    if (_bulkBusy || items.isEmpty) return;
    ref.read(hapticServiceProvider).selectionClick();
    setState(() => _bulkBusy = true);
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    var failed = 0;
    try {
      for (final item in items) {
        if (!mounted) return;
        if (ref
                .read(pdfLibraryControllerProvider)
                .favorites
                .contains(item.path) ==
            favorite) {
          continue;
        }
        try {
          await ctrl.toggleFavorite(item);
        } catch (_) {
          failed++;
        }
      }
      _bulkMessage(failed == 0
          ? (favorite
              ? 'Selected PDFs added to favorites'
              : 'Selected PDFs removed from favorites')
          : 'Could not update $failed PDFs. Selection kept for retry.');
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _deleteSelected(List<PdfFileItem> items) async {
    if (_bulkBusy || items.isEmpty) return;
    setState(() => _bulkBusy = true);
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    final deleted = <String>{};
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
              'Delete ${items.length} ${items.length == 1 ? 'PDF' : 'PDFs'}?'),
          content: Text(
            'Permanently delete these files from your device? This cannot be undone.\n\n${items.map((item) => item.name).join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      for (final item in items) {
        if (!mounted) return;
        try {
          if (!await ctrl.deleteFile(item)) continue;
          deleted.add(item.path);
          if (!mounted) return;
          final index = ref
              .read(openTabsProvider)
              .tabs
              .indexWhere((tab) => tab.path == item.path);
          if (index >= 0) ref.read(openTabsProvider.notifier).closeTab(index);
        } catch (_) {
          // Keep failed files selected; successful deletions must not be retried.
        }
      }
      final failed = items.length - deleted.length;
      _bulkMessage(failed == 0
          ? 'Deleted ${deleted.length} PDFs'
          : 'Deleted ${deleted.length} PDFs. $failed could not be deleted; still selected.');
    } finally {
      if (mounted) {
        setState(() {
          _selectedPaths.removeAll(deleted);
          if (deleted.isNotEmpty && _selectedPaths.isEmpty) {
            _isSelectionMode = false;
          }
          _bulkBusy = false;
        });
      }
    }
  }

  void _showGlassMenu(
      BuildContext context, WidgetRef ref, PdfLibraryController ctrl) {
    showGlassModalBottomSheet(
      context: context,
      builder: (context) {
        final state = ref.read(pdfLibraryControllerProvider);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetActionRow(
                icon: HugeIcons.strokeRoundedRefresh,
                label: 'Refresh Library',
                onTap: () {
                  Navigator.pop(context);
                  ctrl.refresh();
                },
              ),
              const SheetSectionHeader(title: 'Sort By', first: true),
              SheetRadioRow<PdfSortField>(
                value: PdfSortField.name,
                groupValue: state.sortField,
                label: 'Name',
                onChanged: (val) {
                  ctrl.setSortField(val);
                  Navigator.pop(context);
                },
              ),
              SheetRadioRow<PdfSortField>(
                value: PdfSortField.date,
                groupValue: state.sortField,
                label: 'Date Modified',
                onChanged: (val) {
                  ctrl.setSortField(val);
                  Navigator.pop(context);
                },
              ),
              SheetRadioRow<PdfSortField>(
                value: PdfSortField.size,
                groupValue: state.sortField,
                label: 'Size',
                onChanged: (val) {
                  ctrl.setSortField(val);
                  Navigator.pop(context);
                },
              ),
              const SheetSectionHeader(title: 'Order'),
              SheetRadioRow<PdfSortDirection>(
                value: PdfSortDirection.ascending,
                groupValue: state.sortDirection,
                label: 'Ascending',
                onChanged: (val) {
                  ctrl.setSortDirection(val);
                  Navigator.pop(context);
                },
              ),
              SheetRadioRow<PdfSortDirection>(
                value: PdfSortDirection.descending,
                groupValue: state.sortDirection,
                label: 'Descending',
                onChanged: (val) {
                  ctrl.setSortDirection(val);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
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
    Widget content;

    // In selection mode, wrap with custom selection tap
    if (_isSelectionMode) {
      final isSelected = _selectedPaths.contains(item.path);
      content = PdfCustomCard(
        key: key,
        item: item,
        index: index,
        selectionMode: true,
        selected: isSelected,
        scrollController: _scrollController,
        onFavorite: () {},
        onTap: () {
          if (_bulkBusy) return;
          setState(() {
            if (isSelected) {
              _selectedPaths.remove(item.path);
            } else {
              _selectedPaths.add(item.path);
            }
          });
        },
      );
    } else {
      content = PdfCustomCard(
        key: key,
        item: item,
        index: index,
        scrollController: _scrollController,
        onFavorite: () => ctrl.toggleFavorite(item),
        // Delegate long press logic for the Multi-Select (Quick Combine) directly into the card
        onLongPress: () {
          ref.read(hapticServiceProvider).selectionClick();
          setState(() {
            _isSelectionMode = true;
            _selectedPaths.add(item.path);
          });
        },
        onVault: () async {
          final security = ref.read(securityControllerProvider);
          if (!security.isLockEnabled) {
            DynamicIslandNotification.show(context,
                'App lock is not enabled. Enable it in Settings first.',
                icon: HugeIcons.strokeRoundedAlert01);
            return;
          }
          final success = await ref
              .read(vaultControllerProvider.notifier)
              .moveToVault(item);
          if (success && mounted && context.mounted) {
            ref.read(pdfLibraryControllerProvider.notifier).refresh();
            DynamicIslandNotification.show(context, 'Moved to Vault',
                icon: HugeIcons.strokeRoundedFolderSecurity);
          }
        },
        onTap: () async {
          if (item.sizeBytes == 0) {
            PdfErrorHandler.show(context, 'corrupt',
                contextMessage: 'Cannot open empty or corrupted file');
            return;
          }
          await ctrl.markRecent(item);
          if (!context.mounted) return;
          ref.read(openTabsProvider.notifier).openTab(item);
          await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MultiTabViewerScreen()));
        },
      );
    }

    return RepaintBoundary(child: content);
  }

  Future<void> _handleQuickCombine(BuildContext context) async {
    if (_bulkBusy || _selectedPaths.length < 2) return;
    ref.read(hapticServiceProvider).lightImpact();
    final paths = _selectedPaths.toList();
    setState(() {
      _isSelectionMode = false;
      _selectedPaths.clear();
    });

    // Delegate to the merge page but auto-inject the initial paths
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MergePdfsPage(initialFiles: paths),
    ));
  }
}

enum _HomeSelectionAction { selectAll, clear, delete }

class _HomeFilterControl extends StatelessWidget {
  const _HomeFilterControl({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      // Reserve the selection indicator so toggling a chip never shifts labels.
      avatar: selected
          ? Icon(Icons.check_rounded, size: 18, color: colors.onPrimary)
          : const SizedBox(width: 18, height: 18),
      avatarBoxConstraints:
          const BoxConstraints.tightFor(width: 18, height: 18),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: colors.surfaceContainerLow,
      selectedColor: colors.primary,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? colors.onPrimary : colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArcColors.buttonRadius)),
      side: BorderSide(color: selected ? colors.primary : colors.outline),
    );
  }
}

class _HomeResumeCard extends ConsumerWidget {
  const _HomeResumeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(openTabsProvider);
    if (session.tabs.isEmpty) return const SizedBox.shrink();
    final active =
        session.tabs[session.activeIndex.clamp(0, session.tabs.length - 1)];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tabCount = session.tabs.length;
    void resume() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const MultiTabViewerScreen(),
        ));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArcColors.cardRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label:
              'Resume reading ${active.name}. $tabCount ${tabCount == 1 ? 'open tab' : 'open tabs'}',
          excludeSemantics: true,
          onTap: resume,
          child: InkWell(
            key: const ValueKey('home-resume-reading'),
            excludeFromSemantics: true,
            onTap: resume,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.restore_page_rounded,
                            size: 20, color: colors.onSurface),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Resume reading',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded,
                          size: 20, color: colors.onSurface),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(active.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      )),
                  const SizedBox(height: 4),
                  Text('$tabCount ${tabCount == 1 ? 'open tab' : 'open tabs'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
