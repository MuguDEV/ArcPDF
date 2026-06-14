import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/open_tabs_provider.dart';
import 'pdf_viewer_screen.dart';

class MultiTabViewerScreen extends ConsumerStatefulWidget {
  const MultiTabViewerScreen({super.key});

  @override
  ConsumerState<MultiTabViewerScreen> createState() => _MultiTabViewerScreenState();
}

class _MultiTabViewerScreenState extends ConsumerState<MultiTabViewerScreen> {
  late PageController _pageController;

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

  @override
  Widget build(BuildContext context) {
    // Listen to state changes to sync PageController outside of build phase
    ref.listen<OpenTabsState>(openTabsProvider, (previous, next) {
      if (previous?.activeIndex != next.activeIndex && _pageController.hasClients) {
        if (_pageController.page?.round() != next.activeIndex) {
          _pageController.animateToPage(
            next.activeIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    });

    final tabsState = ref.watch(openTabsProvider);
    final tabs = tabsState.tabs;

    if (tabs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const Scaffold();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          ref.read(openTabsProvider.notifier).setActiveIndex(index);
        },
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          return PdfViewerScreen(item: tabs[index]);
        },
      ),
    );
  }
}
