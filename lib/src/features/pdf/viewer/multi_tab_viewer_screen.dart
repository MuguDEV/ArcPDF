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
    final tabsState = ref.watch(openTabsProvider);
    final tabs = tabsState.tabs;

    if (tabs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const Scaffold();
    }

    // Sync PageController with state changes that didn't originate from swiping
    if (_pageController.hasClients && _pageController.page?.round() != tabsState.activeIndex) {
       _pageController.animateToPage(
         tabsState.activeIndex,
         duration: const Duration(milliseconds: 300),
         curve: Curves.easeInOutCubic,
       );
    }

    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        physics: const CustomScrollPhysics(),
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

class CustomScrollPhysics extends ScrollPhysics {
  const CustomScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  CustomScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CustomScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingVelocity => double.infinity; // Prevent accidental fast flings between PDFs
}
