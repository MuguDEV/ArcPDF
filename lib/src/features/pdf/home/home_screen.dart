import 'dart:io';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:install_plugin/install_plugin.dart';

import '../../../shared/widgets/empty_state.dart';
import 'package:flutter/services.dart';
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
import '../../updater/updater_service.dart';
import '../../settings/settings_controller.dart';

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
  Timer? _debounceTimer;

  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};

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
      _checkBackgroundUpdate();
    });
  }

  Future<void> _checkBackgroundUpdate() async {
    final release = await UpdaterService.checkForUpdates();
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
    if (_availableUpdate == null) return;

    setState(() {
      _isDownloadingUpdate = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading update in background...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      // Find universal or any apk
      final response = await http.get(Uri.parse('https://api.github.com/repos/MuguDEV/ArcPDF/releases/latest'));
      String? apkUrl;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> assetsList = data['assets'] ?? [];
        final universalApk = assetsList.firstWhere(
            (a) => (a['name'] as String).contains('universal.apk') || ((a['name'] as String).endsWith('.apk') && !(a['name'] as String).contains('arm') && !(a['name'] as String).contains('x86')),
            orElse: () => null);
        final anyApk = assetsList.firstWhere((a) => (a['name'] as String).endsWith('.apk'), orElse: () => null);

        if (universalApk != null) {
          apkUrl = universalApk['browser_download_url'];
        } else if (anyApk != null) {
          apkUrl = anyApk['browser_download_url'];
        }
      }

      if (apkUrl == null) {
        throw Exception("No APK found in release");
      }

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/ArcPDF_Update.apk';
      final file = File(filePath);

      final dlResponse = await http.get(Uri.parse(apkUrl));
      await file.writeAsBytes(dlResponse.bodyBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Update downloaded!'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Install',
              onPressed: () {
                InstallPlugin.install(file.path);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download update: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingUpdate = false;
          _availableUpdate = null;
        });
      }
    }
  }

  void _ignoreUpdate() {
    if (_availableUpdate != null) {
      ref.read(settingsControllerProvider.notifier).setSkippedUpdateVersion(_availableUpdate!.version);
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
    ref.watch(pdfLibraryControllerProvider.select((s) => s.items));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.sortField));
    ref.watch(pdfLibraryControllerProvider.select((s) => s.sortDirection));
    final selectedTag = ref.watch(pdfLibraryControllerProvider.select((s) => s.selectedTag));

    // Permission gate
    if (!loading && permissionStatus != StoragePermissionStatus.granted) {
      return Scaffold(
        appBar: AppBar(title: const Text('ArcPDF')),
        body: PermissionScreen(status: permissionStatus),
      );
    }

    final items = ctrl.filteredItems();
    final theme = Theme.of(context);


    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: _isSelectionMode
        ? Padding(
            padding: const EdgeInsets.only(bottom: 90.0),
            child: FloatingActionButton.extended(
                onPressed: _selectedPaths.length > 1 ? () => _handleQuickCombine(context) : null,
                backgroundColor: _selectedPaths.length > 1 ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                foregroundColor: _selectedPaths.length > 1 ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                icon: const Icon(HugeIcons.strokeRoundedLayers01),
                label: Text('Combine (${_selectedPaths.length})'),
              ).animate().slideY(begin: 1.0, duration: 250.ms, curve: Curves.easeOutBack),
            )
        : _showScrollToTop
          ? Padding(
              padding: const EdgeInsets.only(bottom: 90.0), // Elevate above the bottom navigation bar
              child: FloatingActionButton(
                  onPressed: () {
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
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator.adaptive(
          onRefresh: ctrl.refresh,
          displacement: 120,
          child: CustomScrollView(
            controller: _scrollController,
            cacheExtent: 500,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
        // Unified app bar (no large duplication)
        if (_availableUpdate != null)
          SliverToBoxAdapter(
            child: Material(
              color: theme.colorScheme.primaryContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(HugeIcons.strokeRoundedPackageOpen, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Available: ${_availableUpdate!.version}',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer),
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
                        onPressed: _isDownloadingUpdate ? null : _downloadAndInstallUpdate,
                        child: _isDownloadingUpdate ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Update'),
                      ),
                    ],
                  ),
                ),
              ),
            ).animate().slideY(begin: -1, duration: 300.ms, curve: Curves.easeOutBack),
          ),

        // Unified app bar (no large duplication)
        GlassSliverAppBar(
          title: Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
            child: _isSelectionMode
              ? Text('${_selectedPaths.length} Selected', style: const TextStyle(fontWeight: FontWeight.w800))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ArcPDF', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      'Your local PDF workspace',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.1,
                          ),
                    ),
                  ],
                ),
          ),
          actions: [
            if (_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedPaths.clear();
                  });
                },
              )
            else
              IconButton(
                icon: const Icon(HugeIcons.strokeRoundedFolderSecurity),
                tooltip: 'Secure Vault',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultScreen()));
                },
              ),
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

        CupertinoSliverRefreshControl(
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            await ctrl.refresh();
          },
        ),

        // Resume Session Banner
        if (ref.watch(openTabsProvider).tabs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MultiTabViewerScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restore_page_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resume Reading',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            Text(
                              'You have ${ref.read(openTabsProvider).tabs.length} tabs open',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ],
                  ),
                ),
              ),
            ).animate().slideY(begin: -0.2, duration: 300.ms, curve: Curves.easeOutBack).fadeIn(),
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
                    onChanged: (val) {
                      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
                      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                        ctrl.setQuery(val);
                      });
                    },
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

                // Tags
                if (ctrl.getAllTags().isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: ctrl.getAllTags().map((tag) {
                        final isSelected = selectedTag == tag;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(tag),
                            selected: isSelected,
                            onSelected: (selected) {
                              HapticFeedback.selectionClick();
                              ctrl.setSelectedTag(selected ? tag : null);
                            },
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                            selectedColor: Theme.of(context).colorScheme.primaryContainer,
                            checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            side: BorderSide.none,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

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
                            onSelected: (_) {
                              HapticFeedback.lightImpact();
                              ctrl.setFilter(f);
                            },
                            label: Text(_label(f)),
                            labelStyle: const TextStyle(height: 1.0),
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
              animated: true,
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
                          child: _buildListItem(context, ref, item, index,
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
              crossAxisCount: 1,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildListItem(context, ref, item, index,
                            key: ValueKey('list_${item.path}'))
                    .animate(key: ValueKey('anim_${item.path}'))
                    .fadeIn(
                      delay: (index > 20 ? 0 : index * 20).ms,
                      duration: 400.ms,
                      curve: Curves.easeOut,
                    )
                    .slideY(
                      begin: 0.15,
                      delay: (index > 20 ? 0 : index * 20).ms,
                      duration: 400.ms,
                      curve: Curves.easeOutCubic,
                    )
                    .scaleXY(
                      begin: 0.92,
                      end: 1.0,
                      delay: (index > 20 ? 0 : index * 20).ms,
                      duration: 400.ms,
                      curve: Curves.easeOutBack,
                    );
              },
              childCount: items.length,
            ),
          ),

        const SliverSafeArea(
          minimum: EdgeInsets.only(bottom: 140),
          sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
      ],
          ),
        ),
      ),
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
      content = GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedPaths.remove(item.path);
              if (_selectedPaths.isEmpty) _isSelectionMode = false;
            } else {
              _selectedPaths.add(item.path);
            }
          });
        },
        child: Stack(
          children: [
            AbsorbPointer(
              child: AnimatedScale(
                scale: isSelected ? 0.95 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: PdfCustomCard(
                  key: key,
                  item: item,
                  index: index,
                  scrollController: _scrollController,
                  onFavorite: () {},
                  onTap: () {},
                ),
              ),
            ),
            if (isSelected)
              Positioned.fill(
                bottom: 12, // match the bottom padding of PdfCustomCard
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 24,
                        ),
                      ).animate().scale(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.elasticOut,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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
          HapticFeedback.selectionClick();
          setState(() {
            _isSelectionMode = true;
            _selectedPaths.add(item.path);
          });
        },
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
          if (item.sizeBytes == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Cannot open empty or corrupted file')),
            );
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
    HapticFeedback.lightImpact();
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
