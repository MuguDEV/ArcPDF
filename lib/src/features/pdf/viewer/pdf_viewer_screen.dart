import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/pdf_file_item.dart';
import '../data/reading_progress_repository.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.item});

  final PdfFileItem item;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> with WidgetsBindingObserver {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  PdfTextSearchResult _searchResult = PdfTextSearchResult();

  Timer? _hideTimer;
  bool _showToolbar = true;
  int _page = 1;
  int _pageCount = 1;
  Timer? _readingTimer;
  int _pendingReadingTime = 0;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

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
    _searchController.dispose();
    _searchFocus.dispose();
    _pdfViewerController.dispose();
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
    setState(() {
      _showToolbar = !_showToolbar;
      if (!_showToolbar && _isSearching) {
        _isSearching = false;
        _searchFocus.unfocus();
        _searchResult.clear();
      }
    });
    if (_showToolbar) _scheduleHide();
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      _searchResult.clear();
      setState(() {});
      return;
    }
    final result = _pdfViewerController.searchText(query);
    setState(() {
      _searchResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          // 1. PDF Viewer
          GestureDetector(
            onTap: _toggleToolbar,
            child: SfPdfViewer.file(
              File(widget.item.path),
              controller: _pdfViewerController,
              canShowPasswordDialog: true, // We will use built-in for now to save hassle and handle gracefully
              enableDocumentLinkAnnotation: true,
              canShowScrollHead: false,
              canShowScrollStatus: false,
              pageSpacing: 4,
              onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                setState(() {
                  _pageCount = _pdfViewerController.pageCount;
                });
              },
              onPageChanged: (PdfPageChangedDetails details) {
                setState(() {
                  _page = details.newPageNumber;
                });
                if (_showToolbar) _scheduleHide();
              },
            ),
          ),

          // 2. Top App Bar / Search Bar
          if (_showToolbar)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 16,
              right: 16,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _showToolbar ? 1.0 : 0.0,
                child: _FrostedBar(
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
                        if (_searchResult.hasResult) ...[
                          Text('${_searchResult.currentInstanceIndex}/${_searchResult.totalInstanceCount}'),
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_up),
                            onPressed: () {
                              _searchResult.previousInstance();
                              setState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down),
                            onPressed: () {
                              _searchResult.nextInstance();
                              setState(() {});
                            },
                          ),
                        ],
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchController.clear();
                              _searchResult.clear();
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
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'info', child: Text('Document Info')),
                            const PopupMenuItem(value: 'share', child: Text('Share PDF')),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // 3. Page Indicator (Bottom)
          if (_showToolbar)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              right: 16,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _showToolbar ? 1.0 : 0.0,
                child: _FrostedBar(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text(
                      '$_page / $_pageCount',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
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
