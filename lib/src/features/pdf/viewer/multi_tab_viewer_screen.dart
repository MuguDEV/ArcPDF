import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/open_tabs_provider.dart';
import '../domain/pdf_file_item.dart';
import 'pdf_viewer_screen.dart';

class MultiTabViewerScreen extends ConsumerStatefulWidget {
  const MultiTabViewerScreen({
    super.key,
    this.viewerBuilder,
    this.edgeSwipeEligibleForTesting,
  });

  /// Allows tab navigation to be tested independently of PDF platform plugins.
  @visibleForTesting
  final Widget Function(BuildContext context, PdfFileItem item)? viewerBuilder;

  /// Simulates reader selection/zoom blocking without loading PDFium.
  @visibleForTesting
  final bool? edgeSwipeEligibleForTesting;

  @override
  ConsumerState<MultiTabViewerScreen> createState() =>
      _MultiTabViewerScreenState();
}

class _MultiTabViewerScreenState extends ConsumerState<MultiTabViewerScreen> {
  static const double _edgeWidth = 28;
  static const double _switchDistance = 72;
  static const double _verticalTolerance = 48;
  static const Duration _edgeGestureTimeout = Duration(milliseconds: 450);
  late final PageController _pageController;
  bool _pageSyncScheduled = false;
  final Set<int> _activePointers = <int>{};
  int? _edgePointer;
  Offset? _edgeStart;
  Offset? _edgeLatest;
  bool _edgeStartedOnLeft = false;
  Duration? _edgeStartedAt;
  bool _edgeGestureBlocked = false;
  Timer? _edgeTimeoutTimer;
  bool _tabSwipeEligible = true;

  bool get _canEdgeSwipe =>
      widget.edgeSwipeEligibleForTesting ?? _tabSwipeEligible;

  @override
  void initState() {
    super.initState();
    _tabSwipeEligible = widget.viewerBuilder != null;
    final activeIndex = ref.read(openTabsProvider).activeIndex;
    _pageController = PageController(initialPage: activeIndex);
  }

  @override
  void dispose() {
    _edgeTimeoutTimer?.cancel();
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

  void _onPointerDown(PointerDownEvent event, double width) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _edgeGestureBlocked = true;
      _edgePointer = null;
      return;
    }
    if (!_canEdgeSwipe || event.kind != PointerDeviceKind.touch) return;
    final onLeft = event.localPosition.dx <= _edgeWidth;
    final onRight = event.localPosition.dx >= width - _edgeWidth;
    if (!onLeft && !onRight) return;
    _edgePointer = event.pointer;
    _edgeStart = event.localPosition;
    _edgeLatest = event.localPosition;
    _edgeStartedOnLeft = onLeft;
    _edgeStartedAt = event.timeStamp;
    _edgeGestureBlocked = false;
    _edgeTimeoutTimer?.cancel();
    _edgeTimeoutTimer = Timer(_edgeGestureTimeout, () {
      _edgeGestureBlocked = true;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _edgePointer) return;
    _edgeLatest = event.localPosition;
    final start = _edgeStart;
    final startedAt = _edgeStartedAt;
    if (start == null ||
        startedAt == null ||
        event.timeStamp - startedAt > _edgeGestureTimeout ||
        (event.localPosition.dy - start.dy).abs() > _verticalTolerance ||
        !_canEdgeSwipe) {
      _edgeGestureBlocked = true;
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer != _edgePointer) {
      if (_activePointers.isEmpty) _resetEdgeGesture();
      return;
    }
    final start = _edgeStart;
    final end = _edgeLatest;
    final startedAt = _edgeStartedAt;
    final state = ref.read(openTabsProvider);
    if (!_edgeGestureBlocked &&
        _canEdgeSwipe &&
        start != null &&
        end != null &&
        startedAt != null &&
        event.timeStamp - startedAt <= _edgeGestureTimeout) {
      final dx = end.dx - start.dx;
      final target = _edgeStartedOnLeft && dx >= _switchDistance
          ? state.activeIndex - 1
          : !_edgeStartedOnLeft && dx <= -_switchDistance
              ? state.activeIndex + 1
              : null;
      if (target != null && target >= 0 && target < state.tabs.length) {
        ref.read(openTabsProvider.notifier).setActiveIndex(target);
      }
    }
    _resetEdgeGesture();
  }

  void _resetEdgeGesture() {
    _edgeTimeoutTimer?.cancel();
    _edgeTimeoutTimer = null;
    _edgePointer = null;
    _edgeStart = null;
    _edgeLatest = null;
    _edgeStartedAt = null;
    _edgeGestureBlocked = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OpenTabsState>(openTabsProvider, (previous, next) {
      if (previous?.activeIndex != next.activeIndex ||
          !identical(previous?.tabs, next.tabs)) {
        if (previous?.activeIndex != next.activeIndex) {
          _tabSwipeEligible = widget.viewerBuilder != null;
          _activePointers.clear();
          _resetEdgeGesture();
        }
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
      body: LayoutBuilder(
          builder: (context, constraints) => Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) =>
                    _onPointerDown(event, constraints.maxWidth),
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerEnd,
                onPointerCancel: _onPointerEnd,
                child: PageView.builder(
                  controller: _pageController,
                  // The PDF viewer owns horizontal drags, text-selection handles, and
                  // pinch gestures. Letting this outer pager compete for the same touch
                  // stream makes a selection at the page edge switch documents and
                  // prevents pinch-to-zoom from completing. The raw listener outside
                  // this pager provides the restricted one-finger edge gesture.
                  physics: const NeverScrollableScrollPhysics(),
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
                            onTabSwipeEligibilityChanged: (eligible) {
                              if (index ==
                                  ref.read(openTabsProvider).activeIndex) {
                                _tabSwipeEligible = eligible;
                              }
                            },
                          ),
                    );
                  },
                ),
              )),
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
