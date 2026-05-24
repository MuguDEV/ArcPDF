import 'dart:async';

import 'dart:ui';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

import '../../settings/settings_controller.dart';
import '../domain/pdf_file_item.dart';
import '../data/reading_progress_repository.dart';
import '../application/pdf_library_controller.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.item});

  final PdfFileItem item;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> with WidgetsBindingObserver {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  late final PdfTextSearcher _textSearcher;

  Timer? _hideTimer;
  bool _showToolbar = true;
  int _page = 1;
  int _pageCount = 1;
  Timer? _readingTimer;
  int _pendingReadingTime = 0;
  bool _fitWidth = true;
  bool _pdfDarkMode = false;
  final int _rotation = 0;
  bool _isFullscreen = false;
  bool _isHorizontalScroll = false;
  Timer? _autoScrollTimer;
  bool _isAutoScrolling = false;

  bool _isSearching = false;
  bool _isReadyToRender = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _textSearcher = PdfTextSearcher(_pdfViewerController);
    WidgetsBinding.instance.addObserver(this);
    _pdfViewerController.addListener(_onPdfViewerChanged);
    _textSearcher.addListener(_onSearcherChanged);
    _scheduleHide();
    _startReadingTimer();

    // Delay rendering slightly to ensure the page transition animation
    // stays at 120fps before locking the thread to load the PDF.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _isReadyToRender = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pdfViewerController.removeListener(_onPdfViewerChanged);
    _textSearcher.removeListener(_onSearcherChanged);
    _hideTimer?.cancel();
    _readingTimer?.cancel();
    _autoScrollTimer?.cancel();
    if (_pendingReadingTime > 0) {
      ref.read(readingProgressRepositoryProvider).addReadTime(widget.item.path, _pendingReadingTime);
    }
    _searchController.dispose();
    _searchFocus.dispose();
    _textSearcher.dispose();

    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    super.dispose();
  }

  void _onPdfViewerChanged() {
    if (_pdfViewerController.isReady) {
      final newPage = _pdfViewerController.pageNumber ?? 1;
      final newPageCount = _pdfViewerController.pageCount;
      if (newPage != _page || newPageCount != _pageCount) {
        setState(() {
          _page = newPage;
          _pageCount = newPageCount;
        });
        ref.read(readingProgressRepositoryProvider).saveLastReadPage(widget.item.path, newPage);
      }
    }
  }

  void _onSearcherChanged() {
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startReadingTimer();
    } else if (state == AppLifecycleState.paused) {
      _readingTimer?.cancel();
      if (_pendingReadingTime > 0) {
        ref.read(readingProgressRepositoryProvider).addReadTime(widget.item.path, _pendingReadingTime);
        _pendingReadingTime = 0;
      }
    }
  }

  void _startReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pendingReadingTime++;
      if (_pendingReadingTime >= 10) {
        ref.read(readingProgressRepositoryProvider).addReadTime(widget.item.path, _pendingReadingTime);
        _pendingReadingTime = 0;
      }
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showToolbar = false);
    });
  }

  void _toggleAutoScroll() {
    setState(() {
      _isAutoScrolling = !_isAutoScrolling;
    });
    if (_isAutoScrolling) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted || !_pdfViewerController.isReady) return;
        final currentCenter = _pdfViewerController.centerPosition;
        if (_isHorizontalScroll) {
          _pdfViewerController.setZoom(Offset(currentCenter.dx + 2, currentCenter.dy), _pdfViewerController.currentZoom);
        } else {
          _pdfViewerController.setZoom(Offset(currentCenter.dx, currentCenter.dy + 2), _pdfViewerController.currentZoom);
        }
      });
      setState(() => _showToolbar = false); // Hide UI for reading
    } else {
      _autoScrollTimer?.cancel();
    }
  }

  void _toggleToolbar() {
    setState(() {
      _showToolbar = !_showToolbar;
      if (!_showToolbar && _isSearching) {
        _isSearching = false;
        _searchFocus.unfocus();
        _textSearcher.resetTextSearch();
      }
    });
    if (_showToolbar) _scheduleHide();
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      _textSearcher.resetTextSearch();
      return;
    }
    _textSearcher.startTextSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBlurEnabled = ref.watch(settingsControllerProvider.select((s) => s.useBlurEffect));
    final isLiquidGlass = ref.watch(settingsControllerProvider.select((s) => s.useLiquidGlass));
    final repo = ref.read(readingProgressRepositoryProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          // 1. PDF Viewer
          if (!_isReadyToRender)
            Center(
              child: Hero(
                tag: 'pdf_thumb_${widget.item.path}',
                child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            Hero(
              tag: 'pdf_thumb_${widget.item.path}',
              child: PdfViewer.file(
                widget.item.path,
              initialPageNumber: repo.getLastReadPage(widget.item.path),
              controller: _pdfViewerController,
              passwordProvider: () async => _showPasswordPrompt(context),
              params: PdfViewerParams(
                errorBannerBuilder: (context, error, stackTrace, documentRef) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: theme.colorScheme.onSurface,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load PDF',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                backgroundColor: theme.colorScheme.surface,
                pageDropShadow: const BoxShadow(color: Colors.transparent),
                enableTextSelection: true,
                margin: 4.0,
                layoutPages: _isHorizontalScroll ? (pages, params) {
                  final height = pages.fold(
                    0.0, (prev, page) => prev > page.height ? prev : page.height) + params.margin * 2;
                  final pageLayouts = <Rect>[];
                  double x = params.margin;
                  for (final page in pages) {
                    pageLayouts.add(Rect.fromLTWH(
                      x, (height - page.height) / 2, page.width, page.height,
                    ));
                    x += page.width + params.margin;
                  }

                  // Handle rotation
                  if (_rotation != 0) {
                    // Note: actual rotation implementation depends on updated pdfrx logic.
                    // Usually handled by re-rendering pages or using an encompassing Transform.
                    // This is a placeholder since rotationAngle was removed from PdfViewerParams.
                  }
                  return PdfPageLayout(pageLayouts: pageLayouts, documentSize: Size(x, height));
                } : null,
                pagePaintCallbacks: [
                  if (_pdfDarkMode)
                    (canvas, pageRect, page) {
                      final paint = Paint()
                        ..blendMode = BlendMode.difference
                        ..color = Colors.white;
                      canvas.drawRect(pageRect, paint);
                    },
                  _textSearcher.pageTextMatchPaintCallback
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
            )),

          // 2. Top App Bar / Search Bar
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            right: 16,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 400),
              curve: Curves.fastLinearToSlowEaseIn,
              offset: _showToolbar ? Offset.zero : const Offset(0, -1.5),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                curve: Curves.fastLinearToSlowEaseIn,
                opacity: _showToolbar ? 1.0 : 0.0,
                child: _FrostedBar(
                  useBlur: isBlurEnabled,
                  useLiquidGlass: isLiquidGlass,
                  child: Row(
                    children: [
                      if (_isSearching) ...[
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            textInputAction: TextInputAction.search,
                            onChanged: (val) {
                              _performSearch(val);
                              _scheduleHide();
                            },
                            decoration: InputDecoration(
                              hintText: 'Search...',
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search_rounded, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        if (_textSearcher.hasMatches) ...[
                          Text('${_textSearcher.currentIndex == null ? 0 : _textSearcher.currentIndex! + 1}/${_textSearcher.matches.length}'),
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_up),
                            onPressed: () {
                              _textSearcher.goToPrevMatch();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down),
                            onPressed: () {
                              _textSearcher.goToNextMatch();
                            },
                          ),
                        ],
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchController.clear();
                              _textSearcher.resetTextSearch();
                            });
                            _scheduleHide();
                          },
                        ),
                      ] else ...[
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.item.name,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true, // Puts icons visually grouped toward the right side
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => setState(() => _pdfDarkMode = !_pdfDarkMode),
                                  icon: Icon(_pdfDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                                  tooltip: _pdfDarkMode ? 'Light Mode' : 'Dark Mode',
                                ),
                                IconButton(
                                  onPressed: () {
                                    ref.read(pdfLibraryControllerProvider.notifier).toggleFavorite(widget.item);
                                    _scheduleHide();
                                  },
                                  icon: Icon(
                                    ref.watch(pdfLibraryControllerProvider.select((s) => s.favorites.contains(widget.item.path)))
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                  ),
                                  tooltip: 'Toggle Favorite',
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() => _fitWidth = !_fitWidth);
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (_fitWidth) {
                                          final m = _pdfViewerController.calcMatrixFitWidthForPage(pageNumber: _pdfViewerController.pageNumber ?? 1);
                                          if (m != null) {
                                            final newZoom = m.getMaxScaleOnAxis(); // TODO: rotation scale
                                            _pdfViewerController.setZoom(_pdfViewerController.centerPosition, newZoom, duration: const Duration(milliseconds: 250));
                                          }
                                        } else {
                                          _pdfViewerController.setZoom(_pdfViewerController.centerPosition, _pdfViewerController.currentZoom / 1.5, duration: const Duration(milliseconds: 250));
                                        }
                                    });
                                  },
                                  icon: Icon(_fitWidth ? Icons.fit_screen_rounded : Icons.width_full_rounded),
                                  tooltip: _fitWidth ? 'Fit Page' : 'Fit Width',
                                ),
                                IconButton(
                                  onPressed: () {
                                    _pdfViewerController.setZoom(_pdfViewerController.centerPosition, _pdfViewerController.currentZoom * 1.5, duration: const Duration(milliseconds: 250));
                                    _scheduleHide();
                                  },
                                  icon: const Icon(Icons.zoom_in_rounded),
                                  tooltip: 'Zoom In',
                                ),
                                IconButton(
                                  onPressed: () {
                                    _pdfViewerController.setZoom(_pdfViewerController.centerPosition, _pdfViewerController.currentZoom / 1.5, duration: const Duration(milliseconds: 250));
                                    _scheduleHide();
                                  },
                                  icon: const Icon(Icons.zoom_out_rounded),
                                  tooltip: 'Zoom Out',
                                ),
                                IconButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rotation is currently disabled in this version.')));
                                    // setState(() => _rotation = (_rotation + 90) % 360);
                                    // _scheduleHide();
                                  },
                                  icon: const Icon(Icons.rotate_right_rounded),
                                  tooltip: 'Rotate Page',
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() => _isHorizontalScroll = !_isHorizontalScroll);
                                    _scheduleHide();
                                  },
                                  icon: Icon(_isHorizontalScroll ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded),
                                  tooltip: 'Toggle Scroll Direction',
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _isFullscreen = !_isFullscreen;
                                      if (_isFullscreen) {
                                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                                      } else {
                                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                                      }
                                    });
                                    _scheduleHide();
                                  },
                                  icon: Icon(_isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                                  tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => _isSearching = true);
                            _searchFocus.requestFocus();
                            _hideTimer?.cancel();
                          },
                          icon: const Icon(Icons.search_rounded),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          onSelected: (val) async {
                            _scheduleHide();
                            if (val == 'info') {
                              await _showPdfInfo();
                            } else if (val == 'share') {
                              Share.shareXFiles([XFile(widget.item.path)]);
                            } else if (val == 'print') {
                              final file = File(widget.item.path);
                              final bytes = await file.readAsBytes();
                              await Printing.layoutPdf(
                                onLayout: (format) async => bytes,
                                name: widget.item.name,
                              );
                            } else if (val == 'outline') {
                              _showDocumentOutline();
                            } else if (val == 'thumbnails') {
                              _showThumbnails();
                            } else if (val == 'jump') {
                              _showJumpToPageDialog();
                            } else if (val == 'autoscroll') {
                              _toggleAutoScroll();
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(value: 'autoscroll', child: Text(_isAutoScrolling ? 'Stop Auto-Scroll' : 'Start Auto-Scroll')),
                            const PopupMenuItem(value: 'jump', child: Text('Jump to Page')),
                            const PopupMenuItem(value: 'thumbnails', child: Text('Page Thumbnails')),
                            const PopupMenuItem(value: 'outline', child: Text('Document Outline')),
                            const PopupMenuItem(value: 'info', child: Text('Document Info')),
                            const PopupMenuItem(value: 'share', child: Text('Share PDF')),
                            const PopupMenuItem(value: 'print', child: Text('Print Document')),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Bottom Scrubber (Slider)
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            left: 16,
            right: 16,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 400),
              curve: Curves.fastLinearToSlowEaseIn,
              offset: _showToolbar ? Offset.zero : const Offset(0, 1.5),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                curve: Curves.fastLinearToSlowEaseIn,
                opacity: _showToolbar ? 1.0 : 0.0,
                child: _FrostedBar(
                  useBlur: isBlurEnabled,
                  useLiquidGlass: isLiquidGlass,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _page > 1
                              ? () {
                                  _pdfViewerController.goToPage(pageNumber: _page - 1);
                                  _scheduleHide();
                                }
                              : null,
                          icon: const Icon(Icons.navigate_before_rounded),
                          tooltip: 'Previous Page',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(36, 36),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_page',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _pageCount > 1 ? _page.toDouble() : 1.0,
                            min: 1.0,
                            max: _pageCount > 1 ? _pageCount.toDouble() : 1.0,
                            divisions: _pageCount > 1 ? _pageCount - 1 : 1,
                            label: '$_page',
                            activeColor: theme.colorScheme.onSurface,
                            inactiveColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                            onChanged: _pageCount > 1
                                ? (value) {
                                    final newPage = value.round();
                                    if (newPage != _page) {
                                      _pdfViewerController.goToPage(pageNumber: newPage);
                                      _scheduleHide();
                                    }
                                  }
                                : null,
                          ),
                        ),
                        Text(
                          '$_pageCount',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _page < _pageCount
                              ? () {
                                  _pdfViewerController.goToPage(pageNumber: _page + 1);
                                  _scheduleHide();
                                }
                              : null,
                          icon: const Icon(Icons.navigate_next_rounded),
                          tooltip: 'Next Page',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(36, 36),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showPasswordPrompt(BuildContext context) async {
    final theme = Theme.of(context);

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String password = '';
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
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
                  child: Icon(Icons.lock_rounded, size: 32, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 24),
                Text('Password Required', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('This document is protected.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                TextField(
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
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
                        Navigator.of(context).pop(); // Exit screen if they cancel
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
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Page Thumbnails', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: _pageCount,
                      itemBuilder: (context, index) {
                        final pageNum = index + 1;
                        return GestureDetector(
                          onTap: () {
                            _pdfViewerController.goToPage(pageNumber: pageNum);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: _page == pageNum ? Border.all(color: theme.colorScheme.primary, width: 3) : null,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (_pdfViewerController.isReady)
                                  PdfPageView(
                                    document: _pdfViewerController.documentRef.resolveListenable().document!,
                                    pageNumber: pageNum,
                                  ),
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$pageNum',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
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
  }

  Future<void> _showJumpToPageDialog() async {
    final theme = Theme.of(context);
    String pageInput = '';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Jump to Page', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '1 - $_pageCount',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => pageInput = val,
                  onSubmitted: (_) {
                    final target = int.tryParse(pageInput);
                    if (target != null && target >= 1 && target <= _pageCount) {
                      _pdfViewerController.goToPage(pageNumber: target);
                    }
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final target = int.tryParse(pageInput);
                        if (target != null && target >= 1 && target <= _pageCount) {
                          _pdfViewerController.goToPage(pageNumber: target);
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('Go'),
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

  Future<void> _showDocumentOutline() async {
    final outline = await _pdfViewerController.documentRef.resolveListenable().document?.loadOutline();
    if (!mounted) return;

    if (outline == null || outline.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No outline found in this document.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Document Outline', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: outline.length,
                      itemBuilder: (context, index) {
                        final node = outline[index];
                        return ListTile(
                          title: Text(node.title),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                          onTap: () {
                            if (node.dest?.pageNumber != null) {
                              _pdfViewerController.goToPage(pageNumber: node.dest!.pageNumber);
                              Navigator.of(context).pop();
                            }
                          },
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
  }

  Future<void> _showPdfInfo() async {
    final theme = Theme.of(context);
    final sizeStr = (widget.item.sizeBytes / (1024 * 1024)).toStringAsFixed(2);
    final dateStr = DateFormat.yMMMd().add_jm().format(widget.item.lastModified);
    
    final repo = ref.read(readingProgressRepositoryProvider);
    final totalTimeSec = repo.getTotalReadTime(widget.item.path);
    final timeStr = '${(totalTimeSec / 60).floor()} min ${totalTimeSec % 60} sec';
    final completionStr = _pageCount > 0 ? '${((_page / _pageCount) * 100).toStringAsFixed(1)}%' : '0%';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
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
                        child: Icon(Icons.info_outline_rounded, color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Document Info',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _InfoRow(icon: Icons.title_rounded, label: 'Name', value: widget.item.name),
                  const Divider(height: 24),
                  _InfoRow(icon: Icons.folder_open_rounded, label: 'Path', value: widget.item.path),
                  const Divider(height: 24),
                  _InfoRow(icon: Icons.data_usage_rounded, label: 'Size', value: '$sizeStr MB'),
                  const Divider(height: 24),
                  _InfoRow(icon: Icons.calendar_today_rounded, label: 'Modified', value: dateStr),
                  const Divider(height: 24),
                  _InfoRow(icon: Icons.file_copy_rounded, label: 'Pages', value: '$_pageCount pages'),
                  const Divider(height: 24),
                  _InfoRow(icon: Icons.timer_rounded, label: 'Total Reading Time', value: timeStr),
                  const Divider(height: 24),
                  _InfoRow(icon: Icons.trending_up_rounded, label: 'Completion', value: completionStr),
                  if (widget.item.isEncrypted) ...[
                    const Divider(height: 24),
                    const _InfoRow(icon: Icons.lock_rounded, label: 'Security', value: 'Password Protected'),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
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
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _FrostedBar extends StatelessWidget {
  const _FrostedBar({required this.child, required this.useBlur, required this.useLiquidGlass});
  final Widget child;
  final bool useBlur;
  final bool useLiquidGlass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBg = isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF5F5F5);

    final double sigma = useLiquidGlass ? 48.0 : 16.0;
    final Color bgColor = useLiquidGlass
        ? (isDark ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4))
        : navBg.withValues(alpha: isDark ? 0.7 : 0.85);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: useBlur ? BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: child),
        ),
      ) : DecoratedBox(
        decoration: BoxDecoration(
          color: navBg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
          ),
        ),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: child),
      ),
    );
  }
}
