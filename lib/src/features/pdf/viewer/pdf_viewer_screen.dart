import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'package:arcpdf/src/shared/theme/arc_theme.dart';
import 'dart:async';

import 'dart:ui';
import 'dart:ui' as ui show Image, TextDirection;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/scheduler.dart';
import '../../../core/utils/logger.dart';
import '../application/pdf_error_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../settings/settings_controller.dart';
import '../../settings/haptic_service.dart';

import '../domain/pdf_file_item.dart';
import '../data/reading_progress_repository.dart';
import '../data/annotation_repository.dart';
import '../data/ocr_module_controller.dart';
import '../data/reflow_engine.dart';
import '../data/reflow_ocr_service.dart';
import '../domain/pdf_annotation.dart';
import '../domain/reflow_document.dart';
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

const _readerSpeechChannel = MethodChannel('com.arcpdf.app/reader_speech');
Object? _readerSpeechHandlerOwner;

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.item,
    this.isActive = true,
    this.onTabSwipeEligibilityChanged,
  });

  final PdfFileItem item;
  final bool isActive;
  final ValueChanged<bool>? onTabSwipeEligibilityChanged;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  GlobalKey _viewerKey = GlobalKey();
  PdfTextSearcher? _textSearcher;
  late final ReadingProgressRepository _progressRepository;
  late final int _initialPage;
  late final double? _initialZoom;
  late final ReadingViewport? _initialViewport;
  late Future<bool> _fileExists;
  Timer? _progressSaveTimer;
  Timer? _loadWatchdog;
  ReadingViewport? _lastSavedViewport;
  bool _restoringProgress = false;
  bool _progressWritable = false;

  bool _documentReady = false;
  bool _loadTimedOut = false;
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
  ReaderLayoutMode _layoutMode = ReaderLayoutMode.continuous;
  late final Ticker _autoScrollTicker;
  Duration? _lastAutoScrollFrame;
  final Stopwatch _openStopwatch = Stopwatch();
  Object? _documentSurfaceKey;
  Widget? _documentSurface;
  bool _loadFailureLogged = false;
  bool _isAutoScrolling = false;
  int _rotationQuarterTurns = 0;

  bool _isSearching = false;
  PdfTextSelection? _textSelection;
  bool _drawingMode = false;
  int _annotationColor = 0xFFFFD54F;
  final List<PdfAnnotation> _annotationUndoStack = [];
  final List<PdfAnnotation> _annotationRedoStack = [];
  List<Offset> _inkPoints = [];
  int? _inkPage;
  double _reflowTextScale = 1.0;
  double _reflowLineSpacing = 1.35;
  bool _isSpeaking = false;
  bool? _lastTabSwipeEligibility;
  final Object _speechHandlerOwner = Object();

  bool _controlsOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  void _installSpeechHandler() {
    _readerSpeechHandlerOwner = _speechHandlerOwner;
    _readerSpeechChannel.setMethodCallHandler((call) async {
      if (call.method == 'completed' && mounted) {
        setState(() => _isSpeaking = false);
      }
    });
  }

  void _removeSpeechHandler() {
    if (!identical(_readerSpeechHandlerOwner, _speechHandlerOwner)) return;
    _readerSpeechHandlerOwner = null;
    _readerSpeechChannel.setMethodCallHandler(null);
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _installSpeechHandler();
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
    _startLoadWatchdog();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSystemUi();
      if (widget.isActive && _keepAwake) WakelockPlus.enable();
    });
  }

  void _startLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted || _documentReady) return;
      setState(() => _loadTimedOut = true);
      _logReader('load.timeout');
    });
  }

  void _retryDocumentLoad() {
    _textSearcher?.removeListener(_onSearcherChanged);
    _textSearcher?.dispose();
    _textSearcher = null;
    setState(() {
      _viewerKey = GlobalKey();
      _fileExists = File(widget.item.path).exists();
      _documentSurface = null;
      _documentSurfaceKey = null;
      _documentReady = false;
      _loadTimedOut = false;
      _loadFailureLogged = false;
      _restoringProgress = false;
      _page = 1;
      _pageCount = 0;
    });
    _startLoadWatchdog();
  }

  @override
  void didUpdateWidget(covariant PdfViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _lastTabSwipeEligibility = null;
        _installSpeechHandler();
        _syncSystemUi();
        _startReadingTimer();
        _scheduleHide();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _notifyTabSwipeEligibility();
        });
      } else {
        _removeSpeechHandler();
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
    _removeSpeechHandler();
    pdfRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _pdfViewerController.removeListener(_onPdfViewerChanged);
    _textSearcher?.removeListener(_onSearcherChanged);
    _logReader('close', fields: {'page': _page, 'ready': _documentReady});
    _openStopwatch.stop();
    _hideTimer?.cancel();
    _loadWatchdog?.cancel();
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
      _notifyTabSwipeEligibility();
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

  void _notifyTabSwipeEligibility() {
    if (!widget.isActive || !_pdfViewerController.isReady) return;
    final eligible = !_drawingMode &&
        !(_textSelection?.hasSelectedText ?? false) &&
        _pdfViewerController.currentZoom <=
            _pdfViewerController.minScale * 1.05;
    if (_lastTabSwipeEligibility == eligible) return;
    _lastTabSwipeEligibility = eligible;
    widget.onTabSwipeEligibilityChanged?.call(eligible);
  }

  void _setTextSelection(PdfTextSelection? selection) {
    if (!mounted) return;
    setState(() => _textSelection = selection);
    _notifyTabSwipeEligibility();
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

  Future<void> _restoreProgressSafely(
      PdfDocument document, PdfViewerController controller) async {
    try {
      await _restoreProgress(document, controller);
    } catch (error, stackTrace) {
      _restoringProgress = false;
      await AppLogger.error(
          'reader.progress.restore_failed', error, stackTrace);
      if (mounted) {
        setState(() {
          _documentReady = true;
          _pageCount = document.pages.length;
          _page = document.pages.isEmpty
              ? 1
              : (controller.pageNumber ?? 1).clamp(1, document.pages.length);
        });
      }
    }
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
    final targetPage = _initialPage.clamp(1, document.pages.length);
    // pdfrx falls back to page one when the saved page exceeds a shortened
    // document. Explicitly anchor the clamped page before restoring zoom.
    var center = controller.pageNumber == targetPage
        ? controller.centerPosition
        : controller.layout.pageLayouts[targetPage - 1].center;
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
    _loadWatchdog?.cancel();
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

  Future<String> _selectedText() async =>
      _pdfViewerController.textSelectionDelegate.getSelectedText();

  Future<void> _copySelectedText() async {
    final text = await _selectedText();
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selected text copied'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _shareSelectedText() async {
    final text = await _selectedText();
    if (text.trim().isEmpty) return;
    await SharePlus.instance.share(ShareParams(
      text: '$text\n\n— ${widget.item.name}',
    ));
  }

  Future<void> _annotateSelection(String type) async {
    final selection = _textSelection;
    if (selection == null || !selection.hasSelectedText) return;
    final ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    var noteText = '';
    if (type == 'note') {
      noteText = await _askForText(
            title: 'Add note',
            label: 'Note for selected text',
          ) ??
          '';
      if (noteText.trim().isEmpty) return;
    }
    final repository = ref.read(annotationRepositoryProvider);
    for (final range in ranges) {
      final bounds = range.bounds;
      if (bounds.isEmpty) continue;
      final annotation = PdfAnnotation(
        id: '${DateTime.now().microsecondsSinceEpoch}-${range.pageNumber}-$type',
        pdfPath: widget.item.path,
        pageNumber: range.pageNumber,
        type: type,
        color: _annotationColor,
        bounds: [bounds.left, bounds.bottom, bounds.right, bounds.top],
        content: type == 'note' ? noteText : range.text,
        createdAt: DateTime.now(),
      );
      await repository.addAnnotation(annotation);
      _annotationUndoStack.add(annotation);
    }
    _annotationRedoStack.clear();
    await _pdfViewerController.textSelectionDelegate.clearTextSelection();
    _setTextSelection(null);
  }

  Future<String?> _askForText({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final annotations = ref
        .watch(annotationRepositoryProvider)
        .getAnnotationsForPdf(widget.item.path);
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
    final cacheMb =
        ref.watch(settingsControllerProvider.select((s) => s.readerCacheMb));
    final preloadExtent = ref
        .watch(settingsControllerProvider.select((s) => s.readerPreloadExtent));
    final surfaceKey = (
      theme.colorScheme,
      reducedMotion,
      lowPowerMode,
      cacheMb,
      preloadExtent,
      _isHorizontalScroll,
      _layoutMode,
      _rotationQuarterTurns,
      _pdfDarkMode,
      _textSearcher,
      annotations.length,
      _drawingMode,
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
          if (_loadTimedOut)
            _buildLoadError(
              context,
              'Loading took too long. Go back and reopen the file. If the '
              'problem continues, the PDF may be damaged or unsupported.',
            )
          else
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
                      _loadWatchdog?.cancel();
                      setState(() {
                        _documentReady = true;
                        _loadTimedOut = false;
                        _pageCount = document.pages.length;
                        _page = document.pages.isEmpty
                            ? 1
                            : (controller.pageNumber ?? 1)
                                .clamp(1, document.pages.length);
                      });
                      _notifyTabSwipeEligibility();
                      unawaited(_restoreProgressSafely(document, controller));
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
                    horizontalCacheExtent:
                        _isHorizontalScroll ? preloadExtent : 0.25,
                    verticalCacheExtent:
                        _isHorizontalScroll ? 0.25 : preloadExtent,
                    maxImageBytesCachedOnMemory: cacheMb * 1024 * 1024,
                    onePassRenderingSizeThreshold: lowPowerMode ? 1200 : 1600,
                    margin: 4.0,
                    sizeDelegateProvider:
                        const PdfViewerSizeDelegateProviderLegacy(maxScale: 8),
                    pageAnchor: _layoutMode == ReaderLayoutMode.singlePage
                        ? PdfPageAnchor.all
                        : PdfPageAnchor.top,
                    buildContextMenu: _buildSelectionContextMenu,
                    textSelectionParams: PdfTextSelectionParams(
                      enabled: !_drawingMode,
                      enableSelectionHandles: true,
                      showContextMenuAutomatically: true,
                      // pdfrx's default triangular handles are very subtle on
                      // scanned pages and can disappear into a dark page
                      // filter. Keep the native selection behavior, but use a
                      // high-contrast Android-style cursor that remains visible
                      // in both themes.
                      buildSelectionHandle: (context, anchor, state) =>
                          _ArcSelectionHandle(
                        color: theme.colorScheme.primary,
                        anchor: anchor,
                        state: state,
                      ),
                      onTextSelectionChange: (selection) {
                        _setTextSelection(selection);
                      },
                    ),
                    matchTextColor:
                        theme.colorScheme.primary.withValues(alpha: 0.16),
                    activeMatchTextColor:
                        theme.colorScheme.primary.withValues(alpha: 0.32),
                    layoutPages: _layoutMode == ReaderLayoutMode.twoPage
                        ? _twoPageLayout
                        : (_isHorizontalScroll ||
                                _layoutMode == ReaderLayoutMode.singlePage)
                            ? (pages, params) {
                                final height = pages.fold(
                                        0.0,
                                        (prev, page) => prev > page.height
                                            ? prev
                                            : page.height) +
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
                      _paintAnnotations,
                    ],
                    pageOverlaysBuilder: _drawingMode
                        ? (context, pageRect, page) => [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) {
                                  setState(() {
                                    _inkPage = page.pageNumber;
                                    _inkPoints = [details.localPosition];
                                  });
                                },
                                onPanUpdate: (details) => setState(() {
                                  _inkPoints = [
                                    ..._inkPoints,
                                    details.localPosition
                                  ];
                                }),
                                onPanEnd: (_) => _finishInk(page, pageRect),
                                child: CustomPaint(
                                  painter: _InkPainter(
                                    points: _inkPage == page.pageNumber
                                        ? _inkPoints
                                        : const [],
                                    color: Color(_annotationColor),
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ]
                        : null,
                    viewerOverlayBuilder: (context, size, handleLinkTap) => [
                      // Keep the visual tap layer pointer-transparent to the
                      // PDF engine. A full-screen GestureDetector competes with
                      // text selection, panning, and pinch-to-zoom in Flutter's
                      // gesture arena.
                      PdfOverlayInteractionRegion(
                        onTap: (details) {
                          if (!handleLinkTap(details.localPosition)) {
                            _toggleToolbar();
                          }
                          return true;
                        },
                        child: SizedBox(width: size.width, height: size.height),
                      ),
                    ],
                  ),
                );

                final selectionColor = _pdfDarkMode
                    ? const Color(0xFFFFC107).withValues(alpha: 0.42)
                    : theme.colorScheme.primary.withValues(alpha: 0.34);
                final themedViewer = Theme(
                  data: theme.copyWith(
                    textSelectionTheme: theme.textSelectionTheme.copyWith(
                      selectionColor: selectionColor,
                      selectionHandleColor: theme.colorScheme.primary,
                    ),
                  ),
                  child: viewer,
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
                            child: themedViewer,
                          )
                        : themedViewer,
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
          if (!_isSearching && _textSelection?.hasSelectedText != true)
            Positioned(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
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
          if (_textSelection?.hasSelectedText == true && !_isSearching)
            Positioned(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
              left: 12,
              right: 12,
              child: _buildSelectionBar(),
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

  PdfPageLayout _twoPageLayout(List<PdfPage> pages, PdfViewerParams params) {
    final layouts = <Rect>[];
    final rows = <List<PdfPage>>[];
    for (var index = 0; index < pages.length; index += 2) {
      rows.add([
        pages[index],
        if (index + 1 < pages.length) pages[index + 1],
      ]);
    }
    final rowHeights = rows
        .map((row) => row.fold<double>(
              0,
              (height, page) => height > page.height ? height : page.height,
            ))
        .toList(growable: false);
    final documentWidth = rows.fold<double>(0, (width, row) {
      final rowWidth = row.fold<double>(0, (sum, page) => sum + page.width) +
          params.margin * (row.length + 1);
      return width > rowWidth ? width : rowWidth;
    });
    var y = params.margin;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final rowHeight = rowHeights[rowIndex];
      var x = (documentWidth -
              row.fold<double>(0, (sum, page) => sum + page.width) -
              params.margin * (row.length - 1)) /
          2;
      for (final page in row) {
        layouts.add(Rect.fromLTWH(
          x,
          y + (rowHeight - page.height) / 2,
          page.width,
          page.height,
        ));
        x += page.width + params.margin;
      }
      y += rowHeight + params.margin;
    }
    return PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(documentWidth, y),
    );
  }

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    final annotations = ref
        .read(annotationRepositoryProvider)
        .getAnnotationsForPage(widget.item.path, page.pageNumber);
    for (final annotation in annotations) {
      final color = Color(annotation.color).withValues(alpha: 0.34);
      final points = annotation.points;
      if (annotation.type == 'ink' && points != null) {
        if (points.length < 4) continue;
        final path = Path();
        for (var i = 0; i + 1 < points.length; i += 2) {
          final point = Offset(
            pageRect.left + points[i] * pageRect.width,
            pageRect.top + points[i + 1] * pageRect.height,
          );
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = Color(annotation.color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }
      if (annotation.bounds.length < 4) continue;
      final pdfRect = PdfRect(
        annotation.bounds[0],
        annotation.bounds[3],
        annotation.bounds[2],
        annotation.bounds[1],
      );
      final rect = pdfRect.toRectInDocument(page: page, pageRect: pageRect);
      if (rect.isEmpty) continue;
      if (annotation.type == 'note') {
        final marker = Offset(rect.right - 7, rect.top + 7);
        canvas.drawCircle(marker, 7, Paint()..color = Color(annotation.color));
        canvas.drawCircle(
            marker,
            7,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
        continue;
      }
      if (annotation.type == 'underline' ||
          annotation.type == 'strikethrough') {
        final lineCount = (annotation.content ?? '')
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .length
            .clamp(1, 100);
        final lineHeight = rect.height / lineCount;
        final paint = Paint()
          ..color = Color(annotation.color)
          ..strokeWidth = 2;
        for (var line = 0; line < lineCount; line++) {
          final y = annotation.type == 'underline'
              ? rect.top + lineHeight * (line + 0.82)
              : rect.top + lineHeight * (line + 0.52);
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
        }
      } else {
        canvas.drawRect(rect, Paint()..color = color);
      }
    }
  }

  Future<void> _finishInk(PdfPage page, Rect pageRect) async {
    final points = _inkPoints;
    if (points.length < 2 || pageRect.width <= 0 || pageRect.height <= 0) {
      if (mounted) setState(() => _inkPoints = []);
      return;
    }
    final normalized = <double>[];
    for (final point in points) {
      normalized
        ..add((point.dx / pageRect.width).clamp(0.0, 1.0))
        ..add((point.dy / pageRect.height).clamp(0.0, 1.0));
    }
    final annotation = PdfAnnotation(
      id: '${DateTime.now().microsecondsSinceEpoch}-ink',
      pdfPath: widget.item.path,
      pageNumber: page.pageNumber,
      type: 'ink',
      color: _annotationColor,
      bounds: const [0, 0, 0, 0],
      points: normalized,
      createdAt: DateTime.now(),
    );
    await ref.read(annotationRepositoryProvider).addAnnotation(annotation);
    _annotationUndoStack.add(annotation);
    _annotationRedoStack.clear();
    if (mounted) {
      setState(() {
        _inkPoints = [];
        _drawingMode = false;
      });
      _scheduleHide();
    }
  }

  Widget _buildReaderHeader(bool ready) {
    final title = widget.item.name
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    final tabsState = ref.watch(openTabsProvider);
    final matchingIndex =
        tabsState.tabs.indexWhere((tab) => tab.path == widget.item.path);
    final tabIndex = matchingIndex >= 0 ? matchingIndex : tabsState.activeIndex;
    final hasPrevious = tabIndex > 0;
    final hasNext = tabIndex >= 0 && tabIndex < tabsState.tabs.length - 1;
    final showArrowButtons =
        MediaQuery.sizeOf(context).width >= 520 && tabsState.tabs.length > 1;

    void selectTab(int index) {
      if (index < 0 || index >= tabsState.tabs.length || index == tabIndex) {
        return;
      }
      ref.read(hapticServiceProvider).selectionClick();
      ref.read(openTabsProvider.notifier).setActiveIndex(index);
    }

    void openTabSwitcher() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TabSwitcherScreen()),
      );
    }

    void startSearch() {
      if (!ready) return;
      _hideTimer?.cancel();
      setState(() => _isSearching = true);
      _searchFocus.requestFocus();
    }

    return Row(
      children: [
        IconButton(
          tooltip: 'Back to library',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(ArcIcons.back),
        ),
        const SizedBox(width: 4),
        if (showArrowButtons)
          IconButton(
            tooltip: 'Previous document tab',
            onPressed: hasPrevious ? () => selectTab(tabIndex - 1) : null,
            icon: const Icon(ArcIcons.previous),
          ),
        Expanded(
          child: _ReaderTabAddressBar(
            title: title,
            position: tabIndex + 1,
            count: tabsState.tabs.length,
            canMovePrevious: hasPrevious,
            canMoveNext: hasNext,
            searchEnabled: ready,
            onOpenTabs: openTabSwitcher,
            onMovePrevious: () => selectTab(tabIndex - 1),
            onMoveNext: () => selectTab(tabIndex + 1),
            onSearch: startSearch,
          ),
        ),
        if (showArrowButtons)
          IconButton(
            tooltip: 'Next document tab',
            onPressed: hasNext ? () => selectTab(tabIndex + 1) : null,
            icon: const Icon(ArcIcons.next),
          ),
        IconButton(
          tooltip: 'Reading controls',
          onPressed: _showReadingControls,
          icon: const Icon(ArcIcons.controls),
        ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('reader-selection-action-dock'),
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _selectionAction(ArcIcons.copy, 'Copy', _copySelectedText),
            _selectionAction(ArcIcons.share, 'Share', _shareSelectedText),
            _selectionAction(ArcIcons.highlight, 'Highlight',
                () => _annotateSelection('highlight')),
            _selectionAction(ArcIcons.underline, 'Underline',
                () => _annotateSelection('underline')),
            _selectionAction(ArcIcons.strikethrough, 'Strike',
                () => _annotateSelection('strikethrough')),
            _selectionAction(
                ArcIcons.note, 'Note', () => _annotateSelection('note')),
            _selectionAction(ArcIcons.close, 'Clear', () async {
              await _pdfViewerController.textSelectionDelegate
                  .clearTextSelection();
              _setTextSelection(null);
            }),
          ],
        ),
      ),
    );
  }

  Widget? _buildSelectionContextMenu(
      BuildContext context, PdfViewerContextMenuBuilderParams params) {
    final delegate = params.textSelectionDelegate;
    final canCopy = params.isTextSelectionEnabled &&
        delegate.isCopyAllowed &&
        delegate.hasSelectedText;
    final canSelectAll =
        params.isTextSelectionEnabled && !delegate.isSelectingAllText;
    if (!canCopy && !canSelectAll) return null;
    final theme = Theme.of(context);

    Widget action(IconData icon, String label, VoidCallback onPressed) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: theme.colorScheme.onSurface,
        ),
      );
    }

    return Material(
      key: const ValueKey('reader-selection-context-menu'),
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 3,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 24,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (canCopy)
              action(ArcIcons.copy, 'Copy', () {
                params.dismissContextMenu();
                unawaited(delegate.copyTextSelection());
              }),
            if (canSelectAll)
              action(ArcIcons.selectAll, 'Select all', () {
                params.dismissContextMenu();
                unawaited(delegate.selectAllText());
              }),
          ],
        ),
      ),
    );
  }

  Widget _selectionAction(IconData icon, String label, VoidCallback onPressed) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        tooltip: label,
        icon: Icon(icon, size: 20),
        constraints: const BoxConstraints(
          minWidth: ArcColors.minTouchTarget,
          minHeight: ArcColors.minTouchTarget,
        ),
      ),
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
              child: Icon(ArcIcons.search)),
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
            icon: const Icon(ArcIcons.close),
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
              icon: const Icon(ArcIcons.previousResult),
            ),
            IconButton(
              tooltip: 'Next search result',
              onPressed: hasMatches ? searcher!.goToNextMatch : null,
              icon: const Icon(ArcIcons.down),
            ),
          ]),
      ],
    );
  }

  Widget _buildPageBar(bool ready) {
    final theme = Theme.of(context);
    final displayPage =
        ready && _pageCount > 0 ? _page.clamp(1, _pageCount) : 1;
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
            icon: Icon(_isAutoScrolling ? ArcIcons.pause : ArcIcons.grid),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: ready && displayPage > 1
                ? () => _goToPage(displayPage - 1)
                : null,
            icon: const Icon(ArcIcons.previous),
          ),
          Expanded(
            child: Tooltip(
              message: 'Jump to page',
              child: TextButton(
                onPressed: ready ? _showJumpToPageDialog : null,
                child: Text(ready ? '$displayPage / $_pageCount' : 'Loading…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: ready && displayPage < _pageCount
                ? () => _goToPage(displayPage + 1)
                : null,
            icon: const Icon(ArcIcons.next),
          ),
        ]),
        if (ready)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: LinearProgressIndicator(
              value:
                  _pageCount > 0 ? (displayPage / _pageCount).clamp(0, 1) : 0,
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
            layoutMode: _layoutMode,
            hasTextSelection: _textSelection?.hasSelectedText == true,
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
      case ReaderAction.layout:
        await _chooseLayoutMode();
      case ReaderAction.bookmarks:
        await _showBookmarks();
      case ReaderAction.reflow:
        await _showReflowReader();
      case ReaderAction.readingSettings:
        await _showReadingSettings();
      case ReaderAction.readAloud:
        await _toggleReadAloud();
      case ReaderAction.annotate:
        await _showAnnotationTools();
      case ReaderAction.selectText:
        if (_textSelection?.hasSelectedText == true) {
          await _copySelectedText();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Long-press text to select it'),
            behavior: SnackBarBehavior.floating,
          ));
        }
    }
  }

  Future<void> _chooseLayoutMode() async {
    final selected = await showModalBottomSheet<ReaderLayoutMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: RadioGroup<ReaderLayoutMode>(
          groupValue: _layoutMode,
          onChanged: (value) {
            if (value != null) Navigator.pop(context, value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Page layout'),
                subtitle: Text('Choose how pages are arranged while reading'),
              ),
              for (final mode in ReaderLayoutMode.values)
                RadioListTile<ReaderLayoutMode>(
                  value: mode,
                  secondary: Icon(switch (mode) {
                    ReaderLayoutMode.continuous => ArcIcons.layoutContinuous,
                    ReaderLayoutMode.singlePage => ArcIcons.layoutSingle,
                    ReaderLayoutMode.twoPage => ArcIcons.layoutTwoPage,
                  }),
                  title: Text(switch (mode) {
                    ReaderLayoutMode.continuous => 'Continuous scroll',
                    ReaderLayoutMode.singlePage => 'Single-page swipe',
                    ReaderLayoutMode.twoPage => 'Two-page spread',
                  }),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _layoutMode = selected;
      _isHorizontalScroll = selected == ReaderLayoutMode.singlePage;
    });
    _pdfViewerController.invalidate();
  }

  Future<void> _showBookmarks() async {
    final repository = ref.read(readingProgressRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (context, setSheetState) {
          final bookmarks = repository.getBookmarks(widget.item.path);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Bookmarks'),
                    subtitle: Text('${bookmarks.length} saved locations'),
                    trailing: IconButton(
                      tooltip: 'Bookmark current page',
                      icon: const Icon(ArcIcons.bookmark),
                      onPressed: () async {
                        final label = await _askForText(
                          title: 'Name bookmark',
                          label: 'Bookmark name',
                        );
                        if (label == null || label.trim().isEmpty) return;
                        final next = [
                          ...bookmarks,
                          ReadingBookmark(
                            id: '${DateTime.now().microsecondsSinceEpoch}',
                            page: _page,
                            label: label.trim(),
                            createdAt: DateTime.now(),
                          ),
                        ];
                        await repository.saveBookmarks(widget.item.path, next);
                        setSheetState(() {});
                      },
                    ),
                  ),
                  if (bookmarks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 12, 24, 28),
                      child: Text('Save pages you want to find quickly later.'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: bookmarks.length,
                        itemBuilder: (context, index) {
                          final bookmark = bookmarks[index];
                          return ListTile(
                            leading: const Icon(ArcIcons.bookmarkSelected),
                            title: Text(bookmark.label),
                            subtitle: Text('Page ${bookmark.page}'),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _goToPage(bookmark.page);
                            },
                            trailing: IconButton(
                              tooltip: 'Delete bookmark',
                              icon: const Icon(ArcIcons.remove),
                              onPressed: () async {
                                final next = bookmarks
                                    .where((item) => item.id != bookmark.id)
                                    .toList();
                                await repository.saveBookmarks(
                                    widget.item.path, next);
                                setSheetState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _showReadingSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reading settings',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text('Text size · ${(_reflowTextScale * 100).round()}%'),
                Slider(
                  value: _reflowTextScale,
                  min: 0.8,
                  max: 1.8,
                  divisions: 10,
                  onChanged: (value) {
                    setSheetState(() => _reflowTextScale = value);
                    setState(() {});
                  },
                ),
                Text('Line spacing · ${_reflowLineSpacing.toStringAsFixed(2)}'),
                Slider(
                  value: _reflowLineSpacing,
                  min: 1.0,
                  max: 2.2,
                  divisions: 12,
                  onChanged: (value) {
                    setSheetState(() => _reflowLineSpacing = value);
                    setState(() {});
                  },
                ),
                const Text('These settings apply to Reflow text mode.'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReadAloud() async {
    if (_isSpeaking) {
      await _readerSpeechChannel.invokeMethod<void>('stop');
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    if (!_pdfViewerController.isReady) return;
    final selected = _textSelection?.hasSelectedText == true
        ? await _selectedText()
        : (await _pdfViewerController.document.pages[_page - 1].loadText())
                ?.fullText ??
            '';
    if (selected.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This page has no readable text'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    try {
      await _readerSpeechChannel
          .invokeMethod<void>('speak', {'text': selected});
      if (mounted) setState(() => _isSpeaking = true);
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Read aloud is available on Android builds'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _showAnnotationTools() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text('Annotation tools'),
              subtitle:
                  Text('Select text to mark it, or draw directly on a page.'),
            ),
            ListTile(
              leading: const Icon(ArcIcons.draw),
              title: const Text('Freehand drawing'),
              onTap: () => Navigator.pop(context, 'draw'),
            ),
            ListTile(
              leading: const Icon(ArcIcons.highlight),
              title: const Text('Choose annotation color'),
              onTap: () => Navigator.pop(context, 'color'),
            ),
            ListTile(
              leading: const Icon(ArcIcons.note),
              title: const Text('Review notes'),
              onTap: () => Navigator.pop(context, 'notes'),
            ),
            ListTile(
              leading: const Icon(ArcIcons.undo),
              title: const Text('Undo annotation'),
              enabled: _annotationUndoStack.isNotEmpty,
              onTap: () => Navigator.pop(context, 'undo'),
            ),
            ListTile(
              leading: const Icon(ArcIcons.redo),
              title: const Text('Redo annotation'),
              enabled: _annotationRedoStack.isNotEmpty,
              onTap: () => Navigator.pop(context, 'redo'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'draw') {
      setState(() => _drawingMode = true);
    } else if (action == 'color') {
      await _chooseAnnotationColor();
    } else if (action == 'notes') {
      await _showNotesList();
    } else if (action == 'undo') {
      await _undoAnnotation();
    } else if (action == 'redo') {
      await _redoAnnotation();
    }
  }

  Future<void> _showNotesList() async {
    final notes = ref
        .read(annotationRepositoryProvider)
        .getAnnotationsForPdf(widget.item.path)
        .where((annotation) => annotation.type == 'note')
        .toList(growable: false);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: notes.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No notes in this document yet.')),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: notes.length,
                itemBuilder: (_, index) {
                  final note = notes[index];
                  return ListTile(
                    leading: Icon(ArcIcons.note, color: Color(note.color)),
                    title: Text(note.content?.trim().isNotEmpty == true
                        ? note.content!
                        : 'Note on page ${note.pageNumber}'),
                    subtitle: Text('Page ${note.pageNumber}'),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _chooseAnnotationColor() async {
    const colors = [0xFFFFD54F, 0xFF81D4FA, 0xFFA5D6A7, 0xFFF48FB1];
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final color in colors)
              IconButton(
                tooltip: 'Use annotation color',
                onPressed: () => Navigator.pop(context, color),
                icon: Icon(Icons.circle, color: Color(color), size: 32),
              ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) {
      setState(() => _annotationColor = selected);
    }
  }

  Future<void> _undoAnnotation() async {
    if (_annotationUndoStack.isEmpty) return;
    final annotation = _annotationUndoStack.removeLast();
    await ref
        .read(annotationRepositoryProvider)
        .deleteAnnotation(annotation.id);
    _annotationRedoStack.add(annotation);
  }

  Future<void> _redoAnnotation() async {
    if (_annotationRedoStack.isEmpty) return;
    final annotation = _annotationRedoStack.removeLast();
    await ref.read(annotationRepositoryProvider).addAnnotation(annotation);
    _annotationUndoStack.add(annotation);
  }

  Future<void> _showReflowReader() async {
    if (!_pdfViewerController.isReady) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _ReflowReaderView(
        document: _pdfViewerController.document,
        engine: ref.read(reflowEngineProvider),
        enableOcr: ref.read(settingsControllerProvider).enableOcr,
        path: widget.item.path,
        initialPage: _page,
        textScale: _reflowTextScale,
        lineSpacing: _reflowLineSpacing,
        onPageChanged: _goToPage,
      ),
    );
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
              ArcIcons.pdf,
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
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _retryDocumentLoad,
                  icon: const Icon(ArcIcons.refresh),
                  label: const Text('Try again'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(ArcIcons.back),
                  label: const Text('Back to library'),
                ),
              ],
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
                  child: Icon(ArcIcons.lock,
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
                    prefixIcon: const Icon(ArcIcons.key),
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
                          icon: const Icon(ArcIcons.close),
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
                      scrollCacheExtent: 200.0,
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
                          child: Icon(ArcIcons.info,
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
                              child: Icon(ArcIcons.close)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _InfoRow(
                        icon: ArcIcons.title,
                        label: 'Name',
                        value: widget.item.name),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: ArcIcons.folderOpen,
                        label: 'Path',
                        value: widget.item.path),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: ArcIcons.fileSize,
                        label: 'Size',
                        value: '$sizeStr MB'),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: ArcIcons.calendar,
                        label: 'Modified',
                        value: dateStr),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: ArcIcons.copy,
                        label: 'Pages',
                        value: '$_pageCount pages'),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: ArcIcons.timer,
                        label: 'Total Reading Time',
                        value: timeStr),
                    const Divider(height: 24),
                    _InfoRow(
                        icon: ArcIcons.progress,
                        label: 'Completion',
                        value: completionStr),
                    if (widget.item.isEncrypted) ...[
                      const Divider(height: 24),
                      const _InfoRow(
                          icon: ArcIcons.lock,
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

    final highContrast = ArcContrast.isHigh(context);
    final blur = useBlur && !lowPowerMode && !highContrast;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: navBg.withValues(alpha: blur ? 0.88 : 1),
        borderRadius: BorderRadius.circular(ArcColors.cardRadius),
        border: Border.all(
            color: highContrast
                ? theme.colorScheme.outline
                : theme.colorScheme.outlineVariant,
            width: highContrast ? 2 : 0.5),
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

/// Chrome-style document address bar. Horizontal swipes are confined to this
/// top control, so PDF selection, panning, and pinch gestures never compete
/// with document-tab navigation.
class _ReaderTabAddressBar extends StatefulWidget {
  const _ReaderTabAddressBar({
    required this.title,
    required this.position,
    required this.count,
    required this.canMovePrevious,
    required this.canMoveNext,
    required this.searchEnabled,
    required this.onOpenTabs,
    required this.onMovePrevious,
    required this.onMoveNext,
    required this.onSearch,
  });

  final String title;
  final int position;
  final int count;
  final bool canMovePrevious;
  final bool canMoveNext;
  final bool searchEnabled;
  final VoidCallback onOpenTabs;
  final VoidCallback onMovePrevious;
  final VoidCallback onMoveNext;
  final VoidCallback onSearch;

  @override
  State<_ReaderTabAddressBar> createState() => _ReaderTabAddressBarState();
}

class _ReaderTabAddressBarState extends State<_ReaderTabAddressBar> {
  double _dragDistance = 0;

  void _finishDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDistance.abs() < 36 && velocity.abs() < 450) return;
    final rtl = Directionality.of(context) == ui.TextDirection.rtl;
    final movingForward = (_dragDistance < 0) != rtl;
    if (movingForward && widget.canMoveNext) {
      widget.onMoveNext();
    } else if (!movingForward && widget.canMovePrevious) {
      widget.onMovePrevious();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final multiple = widget.count > 1;
    final position =
        widget.position.clamp(1, widget.count < 1 ? 1 : widget.count);
    final tabLabel =
        multiple ? 'Tab $position of ${widget.count}' : 'Current document';

    return Semantics(
      container: true,
      label: '${widget.title}, $tabLabel',
      hint: multiple
          ? 'Swipe left or right to change document tabs. Double tap for all tabs.'
          : 'Double tap for open tabs.',
      child: Tooltip(
        message: multiple
            ? '${widget.title} · $position of ${widget.count}. Swipe to change tabs.'
            : widget.title,
        child: Material(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _dragDistance = 0,
            onHorizontalDragUpdate: (details) =>
                _dragDistance += details.primaryDelta ?? 0,
            onHorizontalDragEnd: _finishDrag,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const ValueKey('reader-tab-address'),
                    onTap: widget.onOpenTabs,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 14,
                          end: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (multiple) ...[
                              const SizedBox(width: 8),
                              Text(
                                '$position/${widget.count}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Search document',
                  onPressed: widget.searchEnabled ? widget.onSearch : null,
                  icon: const Icon(ArcIcons.search, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  const _InkPainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _ArcSelectionHandle extends StatelessWidget {
  const _ArcSelectionHandle({
    required this.color,
    required this.anchor,
    required this.state,
  });

  final Color color;
  final PdfTextSelectionAnchor anchor;
  final PdfViewerTextSelectionAnchorHandleState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: CustomPaint(
        painter: _ArcSelectionHandlePainter(
          color: color,
          isStart: anchor.type == PdfTextSelectionAnchorType.a,
          state: state,
        ),
      ),
    );
  }
}

class _ArcSelectionHandlePainter extends CustomPainter {
  const _ArcSelectionHandlePainter({
    required this.color,
    required this.isStart,
    required this.state,
  });

  final Color color;
  final bool isStart;
  final PdfViewerTextSelectionAnchorHandleState state;

  @override
  void paint(Canvas canvas, Size size) {
    final active = state == PdfViewerTextSelectionAnchorHandleState.dragging;
    final handleColor = color.withValues(alpha: active ? 1 : 0.96);
    // The two cursors face each other: the start cursor hangs above the first
    // glyph and the end cursor hangs below the last glyph.
    final center = isStart ? const Offset(32, 33) : const Offset(12, 11);
    final stemEnd = isStart ? const Offset(32, 10) : const Offset(12, 34);
    canvas.drawLine(
      center,
      stemEnd,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.82)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      center,
      stemEnd,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      center,
      stemEnd,
      Paint()
        ..color = handleColor
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.82)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      7.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = handleColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcSelectionHandlePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.isStart != isStart ||
      oldDelegate.state != state;
}

/// Shown in the reflow reader when a scanned page needs OCR that cannot run
/// yet. Ordinary reading stays available through the original page view.
class _OcrPromptCard extends ConsumerWidget {
  const _OcrPromptCard({required this.status, required this.onRetry});

  final ReflowOcrStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final module = ref.watch(ocrModuleControllerProvider);
    final controller = ref.read(ocrModuleControllerProvider.notifier);
    final unsupported = status == ReflowOcrStatus.unsupported ||
        module.state == OcrModuleState.unsupported;
    final busy = module.state == OcrModuleState.downloading ||
        module.state == OcrModuleState.waiting;
    // A deferred wait is scheduled by Play services; offer an immediate start.
    final canStartNow =
        module.state == OcrModuleState.waiting && module.deferred;
    final String message;
    if (unsupported) {
      message = 'This page is scanned and needs text recognition, which is '
          'not available on this device. You can still read the original '
          'page.';
    } else if (status == ReflowOcrStatus.failed) {
      message = 'Text recognition failed for this page. You can try again or '
          'read the original page.';
    } else if (module.state == OcrModuleState.downloading) {
      message = 'Downloading the text recognition component. Google Play '
          'services controls the download.';
    } else if (module.state == OcrModuleState.waiting) {
      message = 'The text recognition download is waiting for Google Play '
          'services to start it.';
    } else {
      message = 'This page is scanned. To read it as text, download the text '
          'recognition component once. Recognition then runs on this device '
          'and nothing is uploaded.';
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(unsupported ? ArcIcons.info : ArcIcons.download, size: 36),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: module.progress),
            ],
            if (!unsupported && (!busy || canStartNow)) ...[
              const SizedBox(height: 12),
              if (status == ReflowOcrStatus.failed)
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                )
              else
                FilledButton.tonal(
                  onPressed: () => module.state == OcrModuleState.failed
                      ? controller.retry()
                      : controller.installNow(),
                  child: Text(module.state == OcrModuleState.failed
                      ? 'Retry'
                      : canStartNow
                          ? 'Download now'
                          : 'Download'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReflowReaderView extends ConsumerStatefulWidget {
  const _ReflowReaderView({
    required this.document,
    required this.engine,
    this.enableOcr = true,
    required this.path,
    required this.initialPage,
    required this.textScale,
    required this.lineSpacing,
    required this.onPageChanged,
  });

  final PdfDocument document;
  final ReflowEngine engine;
  final bool enableOcr;
  final String path;
  final int initialPage;
  final double textScale;
  final double lineSpacing;
  final ValueChanged<int> onPageChanged;

  @override
  ConsumerState<_ReflowReaderView> createState() => _ReflowReaderViewState();
}

class _ReflowReaderViewState extends ConsumerState<_ReflowReaderView> {
  late int _page;
  late double _textScale;
  late double _lineSpacing;
  late final ReflowEngine _engine;
  late Future<ReflowLoadResult> _reflow;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<OcrProgress?> _ocrProgress = ValueNotifier(null);
  OcrCancellationToken _ocrToken = OcrCancellationToken();
  bool _awaitingOcrModule = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(1, widget.document.pages.length);
    _textScale = widget.textScale;
    _lineSpacing = widget.lineSpacing;
    _engine = widget.engine;
    _reflow = _startLoad();
  }

  Future<ReflowLoadResult> _startLoad() {
    // A new load supersedes any OCR work of the previous one.
    _ocrToken.cancel();
    final token = _ocrToken = OcrCancellationToken();
    _ocrProgress.value = null;
    return _engine.loadWithStatus(
      widget.path,
      settings: ReflowSettings(enableOcr: widget.enableOcr),
      cancellation: token,
      onOcrProgress: (progress) {
        if (mounted && !token.isCancelled) _ocrProgress.value = progress;
      },
    ).then((result) {
      _awaitingOcrModule =
          result.needsOcr && result.ocrStatus == ReflowOcrStatus.moduleMissing;
      return result;
    });
  }

  void _reloadReflow() => setState(() => _reflow = _startLoad());

  void _changePage(int page) {
    if (page < 1 || page > widget.document.pages.length) return;
    setState(() {
      _page = page;
    });
    widget.onPageChanged(page);
    // A page selected with the navigation controls is a new reading context.
    // Keeping the previous page's offset makes short pages appear blank or
    // partially scrolled, so always reveal the start of the requested page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _openOriginal() {
    widget.onPageChanged(_page);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Closing the document cancels queued and running OCR for it.
    _ocrToken.cancel();
    _ocrProgress.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyLarge ?? const TextStyle();
    ref.listen<OcrModuleStatus>(ocrModuleControllerProvider, (previous, next) {
      if (next.isReady && _awaitingOcrModule) {
        _awaitingOcrModule = false;
        _reloadReflow();
      }
    });
    return RepaintBoundary(
      key: const ValueKey('reflow-reader-preview'),
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Reflow text · Page $_page',
                          style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'View original page',
                      onPressed: _openOriginal,
                      icon: const Icon(ArcIcons.document),
                    ),
                    IconButton(
                      tooltip: 'Decrease text size',
                      onPressed: _textScale <= 0.8
                          ? null
                          : () => setState(() => _textScale -= 0.1),
                      icon: const Icon(ArcIcons.textSize),
                    ),
                    IconButton(
                      tooltip: 'Increase text size',
                      onPressed: _textScale >= 1.8
                          ? null
                          : () => setState(() => _textScale += 0.1),
                      icon: const Icon(ArcIcons.zoom),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<ReflowLoadResult>(
                  future: _reflow,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<OcrProgress?>(
                              valueListenable: _ocrProgress,
                              builder: (context, progress, _) => Text(
                                progress == null
                                    ? 'Analyzing document layout…'
                                    : 'Recognizing text, page '
                                        '${progress.done} of ${progress.total}…',
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(ArcIcons.error, size: 36),
                              const SizedBox(height: 12),
                              const Text('Reflow analysis failed'),
                              const SizedBox(height: 8),
                              Text('${snapshot.error}',
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: _reloadReflow,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final loaded = snapshot.data!;
                    if (loaded.needsOcr &&
                        loaded.document.ocrPages.contains(_page)) {
                      return _OcrPromptCard(
                        status: loaded.ocrStatus,
                        onRetry: _reloadReflow,
                      );
                    }
                    final blocks = loaded.document
                        .blocksForPage(_page)
                        .where(
                            (block) => block.type != ReflowBlockType.pageBreak)
                        .toList(growable: false);
                    if (blocks.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            switch (loaded.ocrStatus) {
                              ReflowOcrStatus.emptyText =>
                                'Text recognition ran but found no text on this page.',
                              ReflowOcrStatus.disabled =>
                                'No selectable text was found. Turn on text recognition in Settings to read scanned pages.',
                              _ =>
                                'No selectable text or structured regions were found.',
                            },
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      key: PageStorageKey<int>(_page),
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                      itemCount: blocks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) => _ReflowBlockView(
                        key: ValueKey<String>(
                          'reflow-$_page-$index-'
                          '${blocks[index].type.name}-'
                          '${blocks[index].anchor.bounds}',
                        ),
                        block: blocks[index],
                        document: widget.document,
                        baseStyle: baseStyle,
                        textScale: _textScale,
                        lineSpacing: _lineSpacing,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous reflow page',
                      onPressed:
                          _page > 1 ? () => _changePage(_page - 1) : null,
                      icon: const Icon(ArcIcons.previous),
                    ),
                    Expanded(
                      child: Text('$_page / ${widget.document.pages.length}',
                          textAlign: TextAlign.center),
                    ),
                    IconButton(
                      tooltip: 'Next reflow page',
                      onPressed: _page < widget.document.pages.length
                          ? () => _changePage(_page + 1)
                          : null,
                      icon: const Icon(ArcIcons.next),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReflowBlockView extends StatelessWidget {
  const _ReflowBlockView({
    super.key,
    required this.block,
    required this.document,
    required this.baseStyle,
    required this.textScale,
    required this.lineSpacing,
  });

  final ReflowBlock block;
  final PdfDocument document;
  final TextStyle baseStyle;
  final double textScale;
  final double lineSpacing;

  TextStyle _style(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final source = switch (block.type) {
      ReflowBlockType.heading => block.headingLevel == 1
          ? textTheme.headlineSmall
          : textTheme.titleLarge,
      ReflowBlockType.footnote => textTheme.bodySmall,
      ReflowBlockType.equation => textTheme.bodyLarge,
      _ => baseStyle,
    };
    return (source ?? baseStyle).copyWith(
      fontSize: (source?.fontSize ?? baseStyle.fontSize ?? 16) * textScale,
      height: lineSpacing,
      fontFamily: block.type == ReflowBlockType.equation ? 'monospace' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    switch (block.type) {
      case ReflowBlockType.table:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            children: [
              for (final row in block.rows)
                TableRow(
                  children: [
                    for (final cell in row)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(cell, style: style),
                      ),
                  ],
                ),
            ],
          ),
        );
      case ReflowBlockType.image:
      case ReflowBlockType.chart:
      case ReflowBlockType.fallbackRegion:
        return _SourceRegionPreview(
          document: document,
          block: block,
        );
      case ReflowBlockType.list:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: style),
            Expanded(
              child: SelectableText(
                block.text.replaceFirst(
                  RegExp(r'^(?:[•●▪◦‣–-]|\(?\d+[.)]|[a-zA-Z][.)])\s+'),
                  '',
                ),
                style: style,
              ),
            ),
          ],
        );
      case ReflowBlockType.pageBreak:
        return const Divider();
      default:
        return SelectableText(block.text, style: style);
    }
  }
}

class _SourceRegionPreview extends StatefulWidget {
  const _SourceRegionPreview({required this.document, required this.block});

  final PdfDocument document;
  final ReflowBlock block;

  @override
  State<_SourceRegionPreview> createState() => _SourceRegionPreviewState();
}

class _SourceRegionPreviewState extends State<_SourceRegionPreview> {
  ui.Image? _image;
  Object? _error;
  int _renderRevision = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant _SourceRegionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.block.anchor.page != widget.block.anchor.page ||
        oldWidget.block.anchor.bounds != widget.block.anchor.bounds) {
      _renderRevision++;
      _image?.dispose();
      _image = null;
      _error = null;
      _render();
    }
  }

  @override
  void dispose() {
    _renderRevision++;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    final revision = ++_renderRevision;
    try {
      final source = widget.block.anchor;
      final page = await widget.document.pages[source.page - 1].ensureLoaded();
      final rect = source.bounds.intersect(
        Rect.fromLTWH(0, 0, page.width, page.height),
      );
      if (rect.isEmpty) return;
      final scale = math.min(2.0, 900 / rect.width);
      final rendered = await page.render(
        x: (rect.left * scale).floor(),
        y: (rect.top * scale).floor(),
        width: math.max(1, (rect.width * scale).ceil()),
        height: math.max(1, (rect.height * scale).ceil()),
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (rendered == null) return;
      final image = await rendered.createImage();
      rendered.dispose();
      if (!mounted || revision != _renderRevision) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } on Object catch (error) {
      if (mounted && revision == _renderRevision) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = widget.block.caption ??
        switch (widget.block.type) {
          ReflowBlockType.chart => 'Chart',
          ReflowBlockType.image => 'Figure',
          _ => 'Original page region',
        };
    return Semantics(
      image: true,
      label: '$label from page ${widget.block.anchor.page}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: math.max(
                  .5,
                  widget.block.anchor.bounds.width /
                      math.max(1, widget.block.anchor.bounds.height),
                ),
                child: _image != null
                    ? RawImage(image: _image, fit: BoxFit.contain)
                    : Center(
                        child: _error == null
                            ? const CircularProgressIndicator()
                            : const Icon(ArcIcons.image),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Text(
                  '$label · Page ${widget.block.anchor.page}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
