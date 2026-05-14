import 'dart:async';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/pdf_file_item.dart';
import '../domain/pdf_annotation.dart';
import '../data/annotation_repository.dart';
import 'pdf_annotation_overlay.dart';
import 'pdf_text_search_overlay.dart';
import '../data/reading_progress_repository.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.item});

  final PdfFileItem item;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> with WidgetsBindingObserver {
  final _controller = PdfViewerController();
  late final PdfTextSearcher _textSearcher = PdfTextSearcher(_controller)..addListener(_update);
  late final PdfDocumentRef _docRef = PdfDocumentRefFile(
    widget.item.path,
    passwordProvider: () => _promptPassword(),
  );
  Timer? _hideTimer;
  bool _showToolbar = true;
  int _page = 1;
  int _pageCount = 1;
  Timer? _readingTimer;
  int _pendingReadingTime = 0;

  bool _isSearching = false;
  bool _isHighlightMode = false;
  int _highlightColor = 0xFFFFEB3B; // Default yellow
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  void _update() {
    if (mounted) setState(() {});
  }

  List<PdfTextRanges>? _currentSelections;

  void _handleSelection(List<PdfTextRanges>? selections) {
    setState(() {
      if (selections != null && selections.isNotEmpty && selections.any((s) => s.isNotEmpty)) {
        _currentSelections = selections;
      } else {
        _currentSelections = null;
      }
    });
  }

  Future<void> _createHighlight() async {
    final selections = _currentSelections;
    if (selections == null || selections.isEmpty) return;

    final repo = ref.read(annotationRepositoryProvider);

    for (final selection in selections) {
      if (selection.isEmpty) continue;
      final pageText = selection.pageText;

      // Convert ranges to bounds
      final boundsList = <double>[];
      for (final range in selection.ranges) {
          final fragments = PdfTextRangeWithFragments.fromTextRange(pageText, range.start, range.end);
          if (fragments != null) {
             for (final f in fragments.fragments) {
                 boundsList.addAll([
                     f.bounds.left,
                     f.bounds.top,
                     f.bounds.right,
                     f.bounds.bottom,
                 ]);
             }
          }
      }

      if (boundsList.isEmpty) continue;

      final annotation = PdfAnnotation(
        id: '${DateTime.now().millisecondsSinceEpoch}_${pageText.pageNumber}',
        pdfPath: widget.item.path,
        pageNumber: pageText.pageNumber,
        type: 'highlight',
        color: _highlightColor,
        bounds: boundsList, // Storing all bounds continuously [l1,t1,r1,b1, l2,t2,r2,b2...]
        createdAt: DateTime.now(),
      );

      await repo.addAnnotation(annotation);
    }

    // Unfortunately, we cannot programmatically clear the selection cleanly without using internals,
    // but the selection typically goes away when we tap elsewhere. We'll hide our UI.
    setState(() {
        _currentSelections = null;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleHide();
    _startReadingTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _readingTimer?.cancel();
    if (_pendingReadingTime > 0) {
      ref.read(readingProgressRepositoryProvider).addReadTime(widget.item.path, _pendingReadingTime);
    }
    _textSearcher.removeListener(_update);
    _textSearcher.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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

  void _toggleToolbar() {
    if (_isHighlightMode) return; // Intercept tapping in highlight mode
    setState(() {
      _showToolbar = !_showToolbar;
      if (!_showToolbar && _isSearching) {
        _isSearching = false;
        _searchFocus.unfocus();
      }
    });
    if (_showToolbar) _scheduleHide();
  }

  Future<String?> _promptPassword() async {
    String? password;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: _PasswordSheet(
            onSubmit: (val) {
              password = val;
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
    if (password == null && mounted) {
      // If the user dismissed the bottom sheet, pop synchronously so the viewer
      // doesn't flash a broken state or attempt to render a failure.
      Navigator.of(context).pop();
    }
    return password;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleToolbar,
        child: Stack(
          children: [
            Positioned.fill(
              child: PdfViewer(
                _docRef,
                controller: _controller,
                params: PdfViewerParams(
                  pageOverlaysBuilder: (context, pageRect, page) => [
                    PdfAnnotationOverlay(
                      item: widget.item,
                      pageRect: pageRect,
                      page: page,
                    ),
                    PdfTextSearchOverlay(
                      textSearcher: _textSearcher,
                      pageRect: pageRect,
                      page: page,
                    ),
                  ],
                  // Layout pages continuously in a vertical direction
                  layoutPages: (pages, params) {
                    final pageLayouts = <Rect>[];
                    double y = params.margin;
                    double maxWidth = 0;
                    for (final page in pages) {
                      pageLayouts.add(
                        Rect.fromLTWH(
                          params.margin,
                          y,
                          page.width,
                          page.height,
                        ),
                      );
                      y += page.height + params.margin;
                      if (page.width > maxWidth) maxWidth = page.width;
                    }
                    return PdfPageLayout(
                      pageLayouts: pageLayouts,
                      documentSize: Size(maxWidth + params.margin * 2, y),
                    );
                  },
                  maxScale: 6,
                  minScale: 1,
                  enableTextSelection: true,
                  onTextSelectionChange: _handleSelection,
                  onPageChanged: (page) {
                    if (page != null) {
                      setState(() => _page = page);
                      ref.read(readingProgressRepositoryProvider).saveLastReadPage(widget.item.path, page);
                    }
                  },
                  onViewerReady: (document, controller) {
                    setState(() {
                      _pageCount = document.pages.length;
                    });
                    final repo = ref.read(readingProgressRepositoryProvider);
                    final lastPage = repo.getLastReadPage(widget.item.path);
                    if (lastPage > 1 && lastPage <= _pageCount) {
                       _controller.goToPage(pageNumber: lastPage);
                    }
                  },
                  errorBannerBuilder: (context, error, stackTrace, documentRef) {
                    return const SizedBox.shrink();
                  },
                  loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                ),
              ),
            ),
            if (_currentSelections != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 80,
                right: 20,
                child: FloatingActionButton.extended(
                  onPressed: _createHighlight,
                  icon: const Icon(Icons.highlight_rounded),
                  label: const Text('Highlight'),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 12,
              right: 12,
              child: AnimatedSlide(
                duration: 240.ms,
                offset: _showToolbar ? Offset.zero : const Offset(0, -1.2),
                child: AnimatedOpacity(
                  duration: 200.ms,
                  opacity: _showToolbar ? 1 : 0,
                  child: _FrostedBar(
                    child: AnimatedSwitcher(
                      duration: 200.ms,
                      child: _isSearching
                          ? Row(
                              key: const ValueKey('search'),
                              children: [
                                IconButton(
                                  color: theme.colorScheme.onSurface,
                                  onPressed: () {
                                    setState(() {
                                      _isSearching = false;
                                      _searchController.clear();
                                      _textSearcher.resetTextSearch();
                                    });
                                  },
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocus,
                                    style: TextStyle(color: theme.colorScheme.onSurface),
                                    decoration: InputDecoration(
                                      hintText: 'Search...',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                      contentPadding: EdgeInsets.zero,
                                      isDense: true,
                                      fillColor: Colors.transparent,
                                    ),
                                    onChanged: (query) {
                                      if (query.isEmpty) {
                                        _textSearcher.resetTextSearch();
                                      } else {
                                        _textSearcher.startTextSearch(query);
                                      }
                                    },
                                  ),
                                ),
                                if (_textSearcher.hasMatches) ...[
                                  Text(
                                    '${_textSearcher.currentIndex! + 1}/${_textSearcher.matches.length}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
                                  ),
                                  IconButton(
                                    color: theme.colorScheme.onSurface,
                                    onPressed: () => _textSearcher.goToPrevMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                                  ),
                                  IconButton(
                                    color: theme.colorScheme.onSurface,
                                    onPressed: () => _textSearcher.goToNextMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                  ),
                                ],
                              ],
                            )
                          : Row(
                              key: const ValueKey('toolbar'),
                              children: [
                                IconButton(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  onPressed: () => Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                Expanded(
                                  child: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                                ),
                                IconButton(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  onPressed: () {
                                    setState(() => _isSearching = true);
                                    _searchFocus.requestFocus();
                                  },
                                  icon: const Icon(Icons.search_rounded),
                                ),
                                IconButton(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  onPressed: () {
                                    setState(() {
                                      _isHighlightMode = true;
                                      _showToolbar = false;
                                    });
                                  },
                                  icon: const Icon(Icons.border_color_rounded),
                                ),
                                IconButton(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  onPressed: _showPdfInfo,
                                  icon: const Icon(Icons.info_outline_rounded),
                                ),
                                IconButton(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  onPressed: _openThumbnails,
                                  icon: const Icon(Icons.grid_view_rounded),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // Highlight Toolbar Overlay
            if (_isHighlightMode)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                left: 12,
                right: 12,
                child: _FrostedBar(
                  child: Row(
                    children: [
                      IconButton(
                        color: theme.colorScheme.onSurface,
                        onPressed: () => setState(() => _isHighlightMode = false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Spacer(),
                      _buildColorPicker(0xFFFFEB3B, theme),
                      _buildColorPicker(0xFF8BC34A, theme),
                      _buildColorPicker(0xFF03A9F4, theme),
                      _buildColorPicker(0xFFE91E63, theme),
                      const Spacer(),
                      IconButton(
                        color: theme.colorScheme.onSurface,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Note functionality coming soon!')),
                          );
                        },
                        icon: const Icon(Icons.post_add_rounded),
                      ),
                      IconButton(
                        color: theme.colorScheme.onSurface,
                        onPressed: () => Share.shareXFiles([XFile(widget.item.path)]), // ignore: deprecated_member_use
                        icon: const Icon(Icons.ios_share_rounded),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 200.ms).slideY(begin: -1.2),
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              child: AnimatedSlide(
                duration: 240.ms,
                offset: _showToolbar ? Offset.zero : const Offset(0, 1.3),
                child: AnimatedOpacity(
                  duration: 220.ms,
                  opacity: _showToolbar ? 1 : 0,
                  child: _FrostedBar(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          value: _page.toDouble().clamp(1, _pageCount.toDouble()),
                          min: 1,
                          max: _pageCount.toDouble(),
                          onChanged: (value) => _controller.goToPage(pageNumber: value.round()),
                        ),
                        Row(
                          children: [
                            IconButton(color: Theme.of(context).colorScheme.onSurface, onPressed: () => _controller.goToPage(pageNumber: (_page - 1).clamp(1, _pageCount)), icon: const Icon(Icons.chevron_left_rounded)),
                            Text('$_page / $_pageCount', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            const Spacer(),
                            IconButton(color: Theme.of(context).colorScheme.onSurface, onPressed: _controller.zoomDown, icon: const Icon(Icons.zoom_out_rounded)),
                            IconButton(color: Theme.of(context).colorScheme.onSurface, onPressed: _controller.zoomUp, icon: const Icon(Icons.zoom_in_rounded)),
                            IconButton(
                              color: Theme.of(context).colorScheme.onSurface,
                              onPressed: () => _controller.goToPage(pageNumber: (_page + 1).clamp(1, _pageCount)),
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openThumbnails() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.66,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: PdfDocumentViewBuilder(
                documentRef: _docRef,
                builder: (context, document) {
                  if (document == null) return const Center(child: CircularProgressIndicator());
                  return GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: document.pages.length,
                    itemBuilder: (context, index) => InkWell(
                      onTap: () {
                        _controller.goToPage(pageNumber: index + 1, anchor: PdfPageAnchor.top);
                        Navigator.of(context).pop();
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: PdfPageView(document: document, pageNumber: index + 1, alignment: Alignment.center),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorPicker(int color, ThemeData theme) {
    final isSelected = _highlightColor == color;
    return GestureDetector(
      onTap: () => setState(() => _highlightColor = color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: isSelected ? 28 : 24,
        height: isSelected ? 28 : 24,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: theme.colorScheme.onSurface, width: 2) : null,
        ),
      ),
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
  const _FrostedBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBg = isDark ? const Color(0xFF1C1C1C) : const Color(0xFFFCFCFC);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: navBg.withValues(alpha: isDark ? 0.7 : 0.8),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: child),
        ),
      ),
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.onSubmit});
  final ValueChanged<String> onSubmit;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _controller = TextEditingController();
  bool _shaking = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(Icons.lock_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'This PDF is protected',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the password to view this document.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Password',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onSubmitted: (val) {
              if (val.isEmpty) {
                setState(() => _shaking = true);
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) setState(() => _shaking = false);
                });
              } else {
                widget.onSubmit(val);
              }
            },
          )
              .animate(target: _shaking ? 1 : 0)
              .shake(duration: 400.ms, hz: 6),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                if (_controller.text.isEmpty) {
                  setState(() => _shaking = true);
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) setState(() => _shaking = false);
                  });
                } else {
                  widget.onSubmit(_controller.text);
                }
              },
              child: const Text('Unlock'),
            ),
          ),
        ],
      ),
    );
  }
}

