import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/open_tabs_provider.dart';
import '../domain/pdf_file_item.dart';
import 'pdf_viewer_screen.dart';

class MultiTabViewerScreen extends ConsumerStatefulWidget {
  const MultiTabViewerScreen({super.key, this.viewerBuilder});

  /// Allows tab navigation to be tested independently of PDF platform plugins.
  @visibleForTesting
  final Widget Function(BuildContext context, PdfFileItem item)? viewerBuilder;

  @override
  ConsumerState<MultiTabViewerScreen> createState() =>
      _MultiTabViewerScreenState();
}

class _MultiTabViewerScreenState extends ConsumerState<MultiTabViewerScreen> {
  late final PageController _pageController;
  bool _pageSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    final activeIndex = ref.read(openTabsProvider).activeIndex;
    _pageController = PageController(initialPage: activeIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _schedulePageSync() {
    if (_pageSyncScheduled) return;
    _pageSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(openTabsProvider);
      if (state.tabs.isNotEmpty && _pageController.hasClients) {
        // Use the latest state after the new child list has been laid out.
        // Jumping avoids intermediate pages changing the selected document.
        if (_pageController.page != state.activeIndex.toDouble()) {
          _pageController.jumpToPage(state.activeIndex);
        }
      }
      _pageSyncScheduled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OpenTabsState>(openTabsProvider, (previous, next) {
      if (previous?.activeIndex != next.activeIndex ||
          !identical(previous?.tabs, next.tabs)) {
        _schedulePageSync();
      }
    });

    final tabsState = ref.watch(openTabsProvider);
    final tabs = tabsState.tabs;

    if (tabs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(openTabsProvider).tabs.isEmpty) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const Scaffold();
    }

    if (!_pageController.hasClients) _schedulePageSync();

    final indicesByPath = {
      for (var index = 0; index < tabs.length; index++) tabs[index].path: index,
    };

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          // Ignore layout corrections and callbacks from an outdated child list.
          if (_pageSyncScheduled ||
              !identical(tabs, ref.read(openTabsProvider).tabs)) {
            return;
          }
          ref.read(openTabsProvider.notifier).setActiveIndex(index);
        },
        itemCount: tabs.length,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? indicesByPath[key.value] : null,
        itemBuilder: (context, index) {
          final item = tabs[index];
          return _TabPage(
            key: ValueKey(item.path),
            isActive: index == tabsState.activeIndex,
            child: widget.viewerBuilder?.call(context, item) ??
                PdfViewerScreen(
                  key: ValueKey(item.path),
                  item: item,
                  isActive: index == tabsState.activeIndex,
                ),
          );
        },
      ),
    );
  }
}

class _TabPage extends StatefulWidget {
  const _TabPage({super.key, required this.isActive, required this.child});

  final bool isActive;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> with AutomaticKeepAliveClientMixin {
  // Retain the selected viewer while removals shift it outside the old viewport,
  // without keeping inactive PDF viewers and their timers alive indefinitely.
  @override
  bool get wantKeepAlive => widget.isActive;

  @override
  void didUpdateWidget(covariant _TabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
