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
      backgroundColor: Colors.black, // Dark background to enhance the 3D effect
      body: AnimatedBuilder(
        animation: _pageController,
        builder: (context, child) {
          return PageView.builder(
            controller: _pageController,
            physics: const CustomScrollPhysics(),
            onPageChanged: (index) {
              ref.read(openTabsProvider.notifier).setActiveIndex(index);
            },
            itemCount: tabs.length,
            itemBuilder: (context, index) {
              double value = 0.0;
              if (_pageController.position.haveDimensions) {
                value = index - _pageController.page!;
              } else {
                value = (index - tabsState.activeIndex).toDouble();
              }

              // Map the scroll delta (-1 to 1) into a 3D perspective matrix
              value = value.clamp(-1.0, 1.0);
              final Matrix4 transform = Matrix4.identity();
              transform.setEntry(3, 2, 0.001); // Perspective depth

              // Slide elements backwards and rotate them slightly
              final scale = 1.0 - (value.abs() * 0.15);
              final rotationY = value * 0.35; // ~20 degrees
              final opacity = (1.0 - value.abs()).clamp(0.0, 1.0);

              transform.scale(scale); // Uses standard scale uniform method
              transform.rotateY(-rotationY);

              return Transform(
                transform: transform,
                alignment: Alignment.center,
                child: Opacity(
                  opacity: opacity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(value.abs() * 24.0), // Round corners as it shrinks into background
                    child: PdfViewerScreen(item: tabs[index]),
                  ),
                ),
              );
            },
          );
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
