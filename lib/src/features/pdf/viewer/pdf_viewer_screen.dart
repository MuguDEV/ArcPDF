import 'dart:async';

import 'dart:ui';

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter/scheduler.dart';
import '../../../core/utils/logger.dart';
import '../application/pdf_error_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../settings/settings_controller.dart';
import '../../settings/haptic_service.dart';

import '../domain/pdf_file_item.dart';
import '../data/reading_progress_repository.dart';
import '../application/open_tabs_provider.dart';
import '../application/pdf_library_controller.dart';
import 'tab_switcher_screen.dart';
import 'route_observer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'arc_outline_node.dart';
import 'reader_controls_sheet.dart';
import '../../../shared/widgets/arc_bouncy_button.dart';
import '../../../shared/theme/arc_colors.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.item, this.isActive = true});

  final PdfFileItem item;
  final bool isActive;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final GlobalKey _viewerKey = GlobalKey();
  PdfTextSearcher? _textSearcher;
  late final ReadingProgressRepository _progressRepository;
  late final int _initialPage;
  late final double? _initialZoom;
  late final ReadingViewport? _initialViewport;
  late final Future<bool> _fileExists;
  Timer? _progressSaveTimer;
  ReadingViewport? _lastSavedViewport;
  bool _restoringProgress = false;
  bool _progressWritable = false;

  bool _documentReady = false;
  bool _routeVisible = true;
  bool _appActive = true;
  bool _keepAwake = false;
  bool _viewerUpdateScheduled = false;

  Timer? _hideTimer;
  bool _showToolbar = true;
  int _page = 1;
  int _pageCount = 0;
  Timer? _readingTimer;
  int _pendingReadingTime = 0;

  bool _pdfDarkMode = false;
  bool _isFullscreen = false;
  bool _isHorizontalScroll = false;
  late final Ticker _autoScrollTicker;
  Duration? _lastAutoScrollFrame;
  final Stopwatch _openStopwatch = Stopwatch();
  Object? _documentSurfaceKey;
  Widget? _documentSurface;
  bool _loadFailureLogged = false;
  bool _isAutoScrolling = false;
  int _rotationQuarterTurns = 0;

  bool _isSearching = false;

  bool _controlsOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _autoScrollTicker = createTicker(_onAutoScrollFrame);
    _openStopwatch.start();
    _logReader('open');
    _progressRepository = ref.read(readingProgressRepositoryProvider);
    _initialPage = _progressRepository.getLastReadPage(widget.item.path);
    _initialZoom = _progressRepository.getLastZoom(widget.item.path);
    _initialViewport = _progressRepository.getLastViewport(widget.item.path);
    // Check once off the UI thread, not on every page/search/chrome rebuild.
    _fileExists = File(widget.item.path).exists();
    _keepAwake = ref.read(settingsControllerProvider).keepScreenAwake;
    WidgetsBinding.instance.addObserver(this);
    _pdfViewerController.addListener(_onPdfViewerChanged);

    _startReadingTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSystemUi();
      if (widget.isActive && _keepAwake) WakelockPlus.enable();
    });
  }

  @override
  void didUpdateWidget(covariant PdfViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _syncSystemUi();
        _startReadingTimer();
        _scheduleHide();
      } else {
        _pauseReading();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      pdfRouteObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void didPush() {
    // Left intentionally empty as logic moved to didChangeDependencies
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncSystemUi();
    _pauseReading(stopAutoScroll: !_controlsOpen);
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncSystemUi();
    _startReadingTimer();
    _scheduleHide();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _syncSystemUi();
    _pauseReading();
  }

  @override
  void deactivate() {
    // Descendant PDF widgets detach their controller before this state's
    // dispose. Capture while it is still attached, including closed tabs.
    _flushProgress();
    super.deactivate();
  }

  @override
  void dispose() {
    pdfRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _pdfViewerController.removeListener(_onPdfViewerChanged);
    _textSearcher?.removeListener(_onSearcherChanged);
    _logReader('close', fields: {'page': _page, 'ready': _documentReady});
    _openStopwatch.stop();
    _hideTimer?.cancel();
    _readingTimer?.cancel();
    _autoScrollTicker.dispose();
    _flushReadingTime();
    _flushProgress();
    _searchController.dispose();
    _searchFocus.dispose();
    _textSearcher?.dispose();

    // An off-screen tab must not change the active reader's system UI.
    if (widget.isActive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (_keepAwake) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }

    super.dispose();
  }

  void _logReader(String event, {Map<String, Object?> fields = const {}}) {
    unawaited(AppLogger.event('reader.$event', fields: {
      'documentId': AppLogger.documentId(widget.item.path),
      ...fields,
    }));
  }

  void _onPdfViewerChanged() {
    if (!mounted ||
        !_documentReady ||
        _restoringProgress ||
        !_pdfViewerController.isReady ||
        _viewerUpdateScheduled) {
      return;
    }
    _viewerUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewerUpdateScheduled = false;
      if (!mounted ||
          !_documentReady ||
          _restoringProgress ||
          !_pdfViewerController.isReady) {
        return;
      }
      final newPage = _pdfViewerController.pageNumber ?? 1;
      final newPageCount = _pdfViewerController.pageCount;
      if (newPage != _page || newPageCount != _pageCount) {
        setState(() {
          _page = newPage;
          _pageCount = newPageCount;
        });
      }
      if (widget.isActive && _routeVisible && _appActive) {
        // Gesture/auto-scroll updates can arrive every frame. Persist once the
        // view settles, and flush immediately when leaving the reader.
        _progressSaveTimer?.cancel();
        _progressSaveTimer =
            Timer(const Duration(milliseconds: 300), _flushProgress);
      }
    });
  }

  ReadingViewport? _currentViewport() {
    if (!_documentReady ||
        _restoringProgress ||
        !_pdfViewerController.isReady) {
      return null;
    }
    final layouts = _pdfViewerController.layout.pageLayouts;
    final center = _pdfViewerController.centerPosition;
    // pdfrx updates pageNumber on a later frame than its transform. On an
    // immediate exit, anchor to the page actually under the viewport center.
    var low = 0;
    var high = layouts.length - 1;
    var centerPage = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final rect = layouts[mid];
      if (rect.contains(center)) {
        centerPage = mid;
        break;
      }
      final before =
          _isHorizontalScroll ? center.dx < rect.left : center.dy < rect.top;
      if (before) {
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    final page =
        centerPage >= 0 ? centerPage + 1 : _pdfViewerController.pageNumber;
    if (page == null || page < 1 || page > layouts.length) return null;
    final rect = layouts[page - 1];
    if (rect.isEmpty) return null;
    final viewport = ReadingViewport(
      page: page,
      pageCount: _pdfViewerController.pageCount,
      zoom: _pdfViewerController.currentZoom,
      x: (center.dx - rect.left) / rect.width,
      y: (center.dy - rect.top) / rect.height,
    );
    return viewport.isValid ? viewport : null;
  }

  void _flushProgress() {
    _progressSaveTimer?.cancel();
    // Read the controller now, not a pending frame callback: navigation,
    // lifecycle changes, and tab disposal can all happen before that callback.
    final viewport = _currentViewport();
    if (!_progressWritable ||
        viewport == null ||
        viewport.matches(_lastSavedViewport)) {
      return;
    }
    _progressRepository.saveViewport(widget.item.path, viewport);
    _lastSavedViewport = viewport;
  }

  Future<void> _restoreProgress(
      PdfDocument document, PdfViewerController controller) async {
    if (!mounted || _restoringProgress) return;
    _restoringProgress = true;
    final viewport = _initialViewport;
    final zoom = _initialZoom;
    // Never apply an old page-relative offset to a replacement/shortened PDF.
    final canRestorePosition = viewport != null &&
        viewport.isValid &&
        viewport.page == _initialPage &&
        viewport.zoom == zoom &&
        viewport.pageCount == document.pages.length;
    final targetZoom = zoom != null && zoom.isFinite && zoom > 0
        ? zoom.clamp(controller.minScale, controller.maxScale).toDouble()
        : controller.currentZoom;
    var center = controller.centerPosition;
    if (canRestorePosition) {
      final rect = controller.layout.pageLayouts[viewport.page - 1];
      final restoredCenter = Offset(rect.left + viewport.x * rect.width,
          rect.top + viewport.y * rect.height);
      // Finite serialized numbers can still overflow when scaled, or point
      // outside the document. Fall back to the saved page in that case.
      if (restoredCenter.dx.isFinite &&
          restoredCenter.dy.isFinite &&
          (Offset.zero & controller.documentSize).contains(restoredCenter)) {
        center = restoredCenter;
      }
    }
    await controller.goTo(controller.calcMatrixFor(center, zoom: targetZoom),
        duration: Duration.zero);
    if (!mounted || !controller.isReady) return;
    _restoringProgress = false;
    setState(() {
      _documentReady = true;
      _pageCount = document.pages.length;
      _page = controller.pageNumber ?? _initialPage.clamp(1, _pageCount);
    });
    // Persist the normalized page/count even if it matches the displayed page.
    // Inactive preloaded tabs must not overwrite a checkpoint before selection.
    _progressWritable = widget.isActive && _routeVisible && _appActive;
    if (_progressWritable) _flushProgress();
    _logReader('ready', fields: {
      'pages': _pageCount,
      'elapsedMs': _openStopwatch.elapsedMilliseconds,
    });
    _onPdfViewerChanged();
    _scheduleHide();
  }

  void _syncSystemUi() {
    // Only the selected tab may own system UI. Toolbar hiding is independent
    // of fullscreen, so disabling fullscreen stays disabled after auto-hide.
    if (!widget.isActive) return;
    SystemChrome.setEnabledSystemUIMode(
      _isFullscreen && _routeVisible
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
  }

  void _onSearcherChanged() {
    if (mounted) setState(() {});
  }

  void _flushReadingTime() {
    if (_pendingReadingTime == 0) return;
    _progressRepository.addReadTime(widget.item.path, _pendingReadingTime);
    _pendingReadingTime = 0;
  }

  void _pauseReading({bool stopAutoScroll = true}) {
    _readingTimer?.cancel();
    _autoScrollTicker.stop();
    _lastAutoScrollFrame = null;
    if (stopAutoScroll && _isAutoScrolling && mounted) {
      setState(() => _isAutoScrolling = false);
    }
    _hideTimer?.cancel();
    _flushReadingTime();
    _flushProgress();
    _progressWritable = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      _syncSystemUi();
      _startReadingTimer();
      if (widget.isActive && _keepAwake) WakelockPlus.enable();
      _scheduleHide();
    } else {
      _pauseReading();
    }
  }

  void _startReadingTimer() {
    _progressWritable =
        _documentReady && widget.isActive && _routeVisible && _appActive;
    _readingTimer?.cancel();
    _readingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.isActive ||
          !_documentReady ||
          !_routeVisible ||
          !_appActive) {
        return;
      }
      _pendingReadingTime++;
      if (_pendingReadingTime >= 10) _flushReadingTime();
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.isActive ||
        !_documentReady ||
        _isSearching ||
        _controlsOpen ||
        !_routeVisible ||
        !_appActive ||
        MediaQuery.accessibleNavigationOf(context)) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (context.mounted) {
        setState(() {
          _showToolbar = false;
        });
      }
    });
  }

  void _toggleAutoScroll() {
    if (!_pdfViewerController.isReady) return;
    setState(() => _isAutoScrolling = !_isAutoScrolling);
    if (_isAutoScrolling) {
      _startAutoScrollTimer();
      setState(() => _showToolbar = false);
    } else {
      _autoScrollTicker.stop();
      _lastAutoScrollFrame = null;
    }
  }

  void _startAutoScrollTimer() {
    _lastAutoScrollFrame = null;
    if (!_autoScrollTicker.isActive) _autoScrollTicker.start();
  }

  void _onAutoScrollFrame(Duration elapsed) {
    final previous = _lastAutoScrollFrame;
    _lastAutoScrollFrame = elapsed;
    if (previous == null ||
        !mounted ||
        !widget.isActive ||
        !_routeVisible ||
        !_appActive ||
        !_pdfViewerController.isReady ||
        _controlsOpen) {
      return;
    }
    // Keep the reading speed independent of refresh rate; don't catch up after
    // an interrupted frame with a large, visible jump.
    final seconds =
        ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, 0.05);
    final distance = 40 * seconds;
    final center = _pdfViewerController.centerPosition;
    _pdfViewerController.setZoom(
      _isHorizontalScroll
          ? center.translate(distance, 0)
          : center.translate(0, distance),
      _pdfViewerController.currentZoom,
      duration: Duration.zero,
    );
  }

  void _toggleToolbar() {
    setState(() {
      _showToolbar = !_showToolbar;
      if (!_showToolbar) {
        if (_isSearching) {
          _isSearching = false;
          _searchFocus.unfocus();
          _textSearcher?.resetTextSearch();
        }
      }
    });
    if (_showToolbar) _scheduleHide();
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      _textSearcher?.resetTextSearch();
      return;
    }
    _textSearcher?.startTextSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBlurEnabled = ref.watch(settingsControllerProvider
        .select((s) => s.useBlurEffect && !s.lowPowerMode));
    final isLiquidGlass = ref.watch(settingsControllerProvider
        .select((s) => s.useLiquidGlass && !s.lowPowerMode));
    ref.listen<bool>(
        settingsControllerProvider.select((s) => s.keepScreenAwake),
        (_, next) => _keepAwake = next);

    final ready = _documentReady && _pdfViewerController.isReady;
    final reducedMotion = MediaQuery.disableAnimationsOf(context) ||
        ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));

    final lowPowerMode =
        ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));
    final surfaceKey = (
      theme.colorScheme,
      reducedMotion,
      lowPowerMode,
      _isHorizontalScroll,
      _rotationQuarterTurns,
      _pdfDarkMode,
      _textSearcher,
    );
    if (_documentSurfaceKey != surfaceKey) {
      _documentSurfaceKey = surfaceKey;
      _documentSurface = null;
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          // Page counters and chrome changes must not rebuild the PDF renderer.
          _documentSurface ??= FutureBuilder<bool>(
            future: _fileExists,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || snapshot.data != true) {
                return _buildLoadError(
                    context, 'The PDF file is unavailable or empty.');
              }
              final viewer = PdfViewer.file(
                widget.item.path,
                key: _viewerKey,
                initialPageNumber: _initialPage > 0 ? _initialPage : 1,
                controller: _pdfViewerController,
                passwordProvider: () async =>
                    mounted ? _showPasswordPrompt(context) : null,
                params: PdfViewerParams(
                  onViewerReady: (document, controller) {
                    if (!mounted) return;
                    // pdfrx 2.6 requires an attached, ready document here.
                    _textSearcher?.removeListener(_onSearcherChanged);
                    _textSearcher?.dispose();
                    final searcher = PdfTextSearcher(controller);
                    searcher.addListener(_onSearcherChanged);
                    _textSearcher = searcher;
                    unawaited(_restoreProgress(document, controller));
                  },
                  loadingBannerBuilder:
                      (context, bytesDownloaded, totalBytes) =>
                          const Center(child: CircularProgressIndicator()),
                  errorBannerBuilder:
                      (context, error, stackTrace, documentRef) {
                    unawaited(AppLogger.error(
                        'reader.render.failed', error, stackTrace));
                    return _buildLoadError(
                        context,
                        'The file could not be read. It may be damaged, '
                        'password-protected, or no longer accessible. '
                        'Go back and try opening it again.');
                  },
                  backgroundColor: theme.colorScheme.surface,
                  pageDropShadow: null,
                  // InteractiveViewer's default fling stops quickly. Normal
                  // scrolling physics lets fast swipes travel across pages.
                  scrollPhysics: const BouncingScrollPhysics(),
                  scrollPhysicsScale: const ClampingScrollPhysics(),
                  scrollByMouseWheel: 1.0,
                  interactionDelegateProvider: reducedMotion
                      ? const PdfViewerScrollInteractionDelegateProviderInstant()
                      : const PdfViewerScrollInteractionDelegateProviderPhysics(
                          panFriction: 20,
                          zoomFriction: 20,
                        ),
                  horizontalCacheExtent: _isHorizontalScroll ? 1.0 : 0.25,
                  verticalCacheExtent: _isHorizontalScroll ? 0.25 : 1.0,
                  maxImageBytesCachedOnMemory: (lowPowerMode ? 24 : 64) * 1024 * 1024,
                  onePassRenderingSizeThreshold: lowPowerMode ? 1200 : 1600,
                  margin: 4.0,
                  sizeDelegateProvider:
                      const PdfViewerSizeDelegateProviderLegacy(maxScale: 8),
                  matchTextColor:
                      theme.colorScheme.primary.withValues(alpha: 0.16),
                  activeMatchTextColor:
                      theme.colorScheme.primary.withValues(alpha: 0.32),
                  layoutPages: _isHorizontalScroll
                      ? (pages, params) {
                          final height = pages.fold(
                                  0.0,
                                  (prev, page) =>
                                      prev > page.height ? prev : page.height) +
                              params.margin * 2;
                          final pageLayouts = <Rect>[];
                          double x = params.margin;
                          for (final page in pages) {
                            pageLayouts.add(Rect.fromLTWH(
                              x,
                              (height - page.height) / 2,
                              page.width,
                              page.height,
                            ));
                            x += page.width + params.margin;
                          }
                          return PdfPageLayout(
                              pageLayouts: pageLayouts,
                              documentSize: Size(x, height));
                        }
                      : null,
                  pagePaintCallbacks: [
                    if (_textSearcher case final searcher?)
                      searcher.pageTextMatchPaintCallback,
                  ],
                  viewerOverlayBuilder: (context, size, handleLinkTap) => [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) {
                        if (!handleLinkTap(details.localPosition)) {
                          _toggleToolbar();
                        }
                      },
                      child: SizedBox(width: size.width, height: size.height),
                    ),
                  ],
                ),
              );

              return RepaintBoundary(
                child: RotatedBox(
                  quarterTurns: _rotationQuarterTurns,
                  child: _pdfDarkMode
                      ? ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            -0.333,
                            -0.333,
                            -0.333,
                            0,
                            255,
                            -0.333,
                            -0.333,
                            -0.333,
                            0,
                            255,
                            -0.333,
                            -0.333,
                            -0.333,
                            0,
                            255,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ]),
                          child: viewer,
                        )
                      : viewer,
                ),
              );
            },
          ),

          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: _buildChrome(
              reducedMotion: reducedMotion,
              offset: const Offset(0, -1.5),
              child: _FrostedBar(
                useBlur: isBlurEnabled,
                useLiquidGlass: isLiquidGlass,
                child: _isSearching
                    ? _buildSearchBar()
                    : _buildReaderHeader(ready),
              ),
            ),
          ),
          if (!_isSearching)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              left: 12,
              right: 12,
              child: _buildChrome(
                reducedMotion: reducedMotion,
                offset: const Offset(0, 1.5),
                child: _FrostedBar(
                  useBlur: isBlurEnabled,
                  useLiquidGlass: isLiquidGlass,
                  child: _buildPageBar(ready),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChrome({
    required bool reducedMotion,
    required Offset offset,
    required Widget child,
  }) =>
      IgnorePointer(
        ignoring: !_showToolbar,
        child: ExcludeSemantics(
          excluding: !_showToolbar,
          child: AnimatedSlide(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _showToolbar ? Offset.zero : offset,
            child: AnimatedOpacity(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              opacity: _showToolbar ? 1 : 0,
              child: child,
            ),
          ),
        ),
      );

  Widget _buildReaderHeader(bool ready) {
    final theme = Theme.of(context);
    final title = widget.item.name
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to library',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Tooltip(
            message: widget.item.name,
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
        ArcBouncyButton(
          tooltip: 'Search document',
          onPressed: !ready
              ? null
              : () {
                  _hideTimer?.cancel();
                  setState(() => _isSearching = true);
                  _searchFocus.requestFocus();
                },
          child: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'Reading controls',
          onPressed: _showReadingControls,
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final searcher = _textSearcher;
    final searching = searcher?.isSearching == true ||
        searcher?.pattern != _searchController.text;
    final hasMatches = searcher?.hasMatches ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Padding(
              padding: EdgeInsets.only(left: 12, right: 8),
              child: Icon(Icons.search_rounded)),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Find in document',
                labelText: 'Search document',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (query) {
                _performSearch(query);
                setState(() {});
              },
            ),
          ),
          IconButton(
            tooltip: 'Close search',
            onPressed: () {
              _searchFocus.unfocus();
              _searchController.clear();
              _textSearcher?.resetTextSearch();
              setState(() => _isSearching = false);
              _scheduleHide();
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
        if (_searchController.text.isNotEmpty)
          Row(children: [
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                  liveRegion: true,
                  child: Text(
                    hasMatches
                        ? '${(searcher!.currentIndex ?? -1) + 1} of ${searcher.matches.length} matches'
                        : searching
                            ? 'Searching…'
                            : 'No matches found',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
            ),
            IconButton(
              tooltip: 'Previous search result',
              onPressed: hasMatches ? searcher!.goToPrevMatch : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: 'Next search result',
              onPressed: hasMatches ? searcher!.goToNextMatch : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ]),
      ],
    );
  }

  Widget _buildPageBar(bool ready) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          IconButton(
            tooltip: _isAutoScrolling ? 'Stop auto scroll' : 'Page thumbnails',
            onPressed: !ready
                ? null
                : _isAutoScrolling
                    ? _toggleAutoScroll
                    : _showThumbnails,
            icon: Icon(_isAutoScrolling
                ? Icons.pause_rounded
                : Icons.grid_view_rounded),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: ready && _page > 1 ? () => _goToPage(_page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Tooltip(
              message: 'Jump to page',
              child: TextButton(
                onPressed: ready ? _showJumpToPageDialog : null,
                child: Text(ready ? '$_page / $_pageCount' : 'Not loaded',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed:
                ready && _page < _pageCount ? () => _goToPage(_page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
        if (ready)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: LinearProgressIndicator(
              value: _pageCount > 0 ? (_page / _pageCount).clamp(0, 1) : 0,
              minHeight: 2,
              borderRadius: BorderRadius.circular(2),
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.12),
              color: theme.colorScheme.onSurface,
            ),
          ),
      ],
    );
  }

  void _goToPage(int page) {
    if (!_pdfViewerController.isReady) return;
    final target = page.clamp(1, _pageCount);
    _logReader('page.jump', fields: {'from': _page, 'to': target});
    final reducedMotion = MediaQuery.disableAnimationsOf(context) ||
        ref.read(settingsControllerProvider).lowPowerMode;
    _pdfViewerController.goToPage(
      pageNumber: target,
      duration:
          reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
    );
    _scheduleHide();
  }

  Future<void> _showReadingControls() async {
    if (_controlsOpen) return;
    _hideTimer?.cancel();
    _controlsOpen = true;
    _logReader('controls.open');
    try {
      final isFavorite = ref
          .read(pdfLibraryControllerProvider)
          .favorites
          .contains(widget.item.path);
      final tabCount = ref.read(openTabsProvider).tabs.length;
      final action = await showModalBottomSheet<ReaderAction>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88),
          child: ReaderControlsSheet(
            title: widget.item.name,
            page: _page,
            pageCount: _pageCount,
            ready: _documentReady && _pdfViewerController.isReady,
            darkPages: _pdfDarkMode,
            isFavorite: isFavorite,
            horizontalScroll: _isHorizontalScroll,
            autoScroll: _isAutoScrolling,
            keepAwake: _keepAwake,
            fullscreen: _isFullscreen,
            tabCount: tabCount,
            onSelected: (action) => Navigator.pop(sheetContext, action),
          ),
        ),
      );
      if (!mounted || action == null) return;
      await _handleReaderAction(action);
    } catch (error, stack) {
      unawaited(AppLogger.error('reader.action.failed', error, stack));
      if (mounted) {
        PdfErrorHandler.show(context, error,
            contextMessage: 'Could not complete document action');
      }
    } finally {
      _logReader('controls.close');
      _controlsOpen = false;
      if (mounted) {
        if (_isAutoScrolling && _routeVisible && _appActive) {
          _startAutoScrollTimer();
        }
        _scheduleHide();
      }
    }
  }

  Future<void> _handleReaderAction(ReaderAction action) async {
    _logReader('action', fields: {'action': action.name, 'page': _page});
    final reducedMotion = MediaQuery.disableAnimationsOf(context) ||
        ref.read(settingsControllerProvider).lowPowerMode;
    switch (action) {
      case ReaderAction.pageColors:
        setState(() => _pdfDarkMode = !_pdfDarkMode);
      case ReaderAction.favorite:
        ref.read(hapticServiceProvider).selectionClick();
        await ref
            .read(pdfLibraryControllerProvider.notifier)
            .toggleFavorite(widget.item);
      case ReaderAction.fitWidth:
      case ReaderAction.fitPage:
        if (!_pdfViewerController.isReady) return;
        final matrix = action == ReaderAction.fitWidth
            ? _pdfViewerController.calcMatrixFitWidthForPage(pageNumber: _page)
            : _pdfViewerController.calcMatrixForFit(pageNumber: _page);
        if (matrix != null) {
          await _pdfViewerController.goTo(matrix,
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220));
        }
      case ReaderAction.scrollDirection:
        setState(() => _isHorizontalScroll = !_isHorizontalScroll);
      case ReaderAction.rotate:
        setState(() => _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4);
      case ReaderAction.fullscreen:
        setState(() {
          _isFullscreen = !_isFullscreen;
          _showToolbar = !_isFullscreen;
        });
        _syncSystemUi();
      case ReaderAction.autoScroll:
        _toggleAutoScroll();
      case ReaderAction.keepAwake:
        final next = !_keepAwake;
        await ref
            .read(settingsControllerProvider.notifier)
            .setKeepScreenAwake(next);
        await WakelockPlus.toggle(enable: next);
      case ReaderAction.thumbnails:
        await _showThumbnails();
      case ReaderAction.outline:
        await _showDocumentOutline();
      case ReaderAction.info:
        await _showPdfInfo();
      case ReaderAction.share:
        await SharePlus.instance
            .share(ShareParams(files: [XFile(widget.item.path)]));
      case ReaderAction.sharePage:
        await _shareCurrentPage();
      case ReaderAction.print:
        final bytes = await File(widget.item.path).readAsBytes();
        if (!mounted) return;
        await Printing.layoutPdf(
            onLayout: (_) async => bytes, name: widget.item.name);
      case ReaderAction.tabs:
        await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TabSwitcherScreen()));
    }
  }

  Widget _buildLoadError(BuildContext context, String message) {
    if (!_loadFailureLogged) {
      _loadFailureLogged = true;
      _logReader('load.failed');
    }
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to open PDF',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to library'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareCurrentPage() async {
    if (!_pdfViewerController.isReady) return;
    final sharedPage = _page;
    try {
      final doc = _pdfViewerController.document;
      final page = doc.pages[sharedPage - 1];

      final pdfImage = await page.render(
        width: page.width.toInt(),
        height: page.height.toInt(),
        backgroundColor: 0xffffffff,
      );

      if (pdfImage == null) return;
      if (pdfImage.pixels.isEmpty) {
        pdfImage.dispose();
        return;
      }
      final image = await pdfImage.createImage().whenComplete(pdfImage.dispose);
      final ByteData? byteData;
      try {
        byteData = await image.toByteData(format: ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (byteData == null || !mounted) return;

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path,
          'page_${sharedPage}_${DateTime.now().microsecondsSinceEpoch}.png'));
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          text: 'Page $sharedPage from ${widget.item.name}',
        ),
      );
    } catch (e) {
      if (mounted) {
        PdfErrorHandler.show(context, e,
            contextMessage: 'Failed to extract and share page');
      }
    }
  }

  Future<String?> _showPasswordPrompt(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        String password = '';
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_rounded,
                      size: 32, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 24),
                Text('Password Required',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('This document is protected.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                TextField(
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Document password',
                    hintText: 'Enter password',
                    prefixIcon: const Icon(Icons.key_rounded),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => password = val,
                  onSubmitted: (_) => Navigator.of(context).pop(password),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(password),
                      child: const Text('Unlock'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showThumbnails() async {
    _logReader('pages.open');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pages',
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              Text('$_pageCount pages · Current page $_page',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close pages',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(20, 12, 20,
                          MediaQuery.paddingOf(context).bottom + 20),
                      cacheExtent: 200.0,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: _pageCount,
                      itemBuilder: (context, index) {
                        final pageNum = index + 1;
                        return Semantics(
                          button: true,
                          selected: _page == pageNum,
                          label: 'Page $pageNum',
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius:
                                BorderRadius.circular(ArcColors.buttonRadius),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).pop();
                                _goToPage(pageNum);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      ArcColors.buttonRadius),
                                  border: Border.all(
                                    color: _page == pageNum
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.5),
                                    width: _page == pageNum ? 2 : 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (_pdfViewerController.isReady)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 10, 10, 34),
                                        child: RepaintBoundary(
                                          child: PdfPageView(
                                            document:
                                                _pdfViewerController.document,
                                            pageNumber: pageNum,
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      bottom: 8,
                                      left: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _page == pageNum
                                              ? theme.colorScheme.onSurface
                                              : theme.colorScheme
                                                  .surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(
                                              ArcColors.pillRadius),
                                        ),
                                        child: Text(
                                          '$pageNum',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                            color: _page == pageNum
                                                ? theme.colorScheme.surface
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    _logReader('pages.close');
  }

  Future<void> _showJumpToPageDialog() async {
    if (!_pdfViewerController.isReady) return;
    final formKey = GlobalKey<FormState>();
    var pageInput = '$_page';
    final pageCount = _pageCount;
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (formKey.currentState?.validate() ?? false) {
            Navigator.pop(dialogContext, int.parse(pageInput.trim()));
          }
        }

        return AlertDialog(
          scrollable: true,
          title: const Text('Go to page'),
          content: Form(
            key: formKey,
            child: TextFormField(
              initialValue: pageInput,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                  labelText: 'Page number', helperText: '1 to $pageCount'),
              onChanged: (value) => pageInput = value,
              onFieldSubmitted: (_) => submit(),
              validator: (value) {
                final page = int.tryParse(value?.trim() ?? '');
                return page == null || page < 1 || page > pageCount
                    ? 'Enter a page from 1 to $pageCount'
                    : null;
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Go to page')),
          ],
        );
      },
    );
    if (mounted && target != null) _goToPage(target);
  }

  Future<void> _showDocumentOutline() async {
    if (!_pdfViewerController.isReady) return;
    final outline = await _pdfViewerController.document.loadOutline();
    if (!mounted) return;

    if (outline.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No outline found in this document.'),
            behavior: SnackBarBehavior.floating),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Document Outline',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: outline.length,
                        itemBuilder: (context, index) {
                          return ArcOutlineNode(
                            node: outline[index],
                            level: 0,
                            onTap: (page) {
                              _pdfViewerController.goToPage(pageNumber: page);
                              Navigator.of(context).pop();
                            },
                          )
                              .animate()
                              .fadeIn(
                                delay: (index > 20 ? 0 : index * 30).ms,
                                duration: 300.ms,
                                curve: Curves.easeOut,
                              )
                              .slideY(
                                begin: 0.1,
                                duration: 300.ms,
                                curve: Curves.easeOutBack,
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPdfInfo() async {
    final sizeStr = (widget.item.sizeBytes / (1024 * 1024)).toStringAsFixed(2);
    final dateStr =
        DateFormat.yMMMd().add_jm().format(widget.item.lastModified);

    final repo = ref.read(readingProgressRepositoryProvider);
    final totalTimeSec = repo.getTotalReadTime(widget.item.path);
    final timeStr =
        '${(totalTimeSec / 60).floor()} min ${totalTimeSec % 60} sec';
    final completionStr = _pageCount > 0
        ? '${((_page / _pageCount) * 100).toStringAsFixed(1)}%'
        : 'Not loaded';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Icon(Icons.info_outline_rounded,
                              color: theme.colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Document Info',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ArcBouncyButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.close_rounded)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _InfoRow(
                        icon: Icons.title_rounded,
                        label: 'Name',
                        value: widget.item.name),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: Icons.folder_open_rounded,
                        label: 'Path',
                        value: widget.item.path),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: Icons.data_usage_rounded,
                        label: 'Size',
                        value: '$sizeStr MB'),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: Icons.calendar_today_rounded,
                        label: 'Modified',
                        value: dateStr),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: Icons.file_copy_rounded,
                        label: 'Pages',
                        value: '$_pageCount pages'),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: Icons.timer_rounded,
                        label: 'Total Reading Time',
                        value: timeStr),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: Icons.trending_up_rounded,
                        label: 'Completion',
                        value: completionStr),
                    if (widget.item.isEncrypted) ...[
                      const Divider(height: 24),
                      const _InfoRow(
                          icon: Icons.lock_rounded,
                          label: 'Security',
                          value: 'Password Protected'),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _FrostedBar extends ConsumerWidget {
  const _FrostedBar(
      {required this.child,
      required this.useBlur,
      required this.useLiquidGlass});
  final Widget child;
  final bool useBlur;
  final bool useLiquidGlass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final navBg = theme.colorScheme.surfaceContainerLow;
    final lowPowerMode =
        ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));

    final blur = useBlur && !lowPowerMode;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: navBg.withValues(alpha: blur ? 0.88 : 1),
        borderRadius: BorderRadius.circular(ArcColors.cardRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: child,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(ArcColors.cardRadius),
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(
                  sigmaX: useLiquidGlass ? 24 : 12,
                  sigmaY: useLiquidGlass ? 24 : 12),
              child: content,
            )
          : content,
    );
  }
}
