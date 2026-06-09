import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../pdf/application/pdf_library_controller.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../pdf/home/widgets/pdf_thumbnail.dart';

class InAppPdfSelector extends ConsumerStatefulWidget {
  const InAppPdfSelector({
    super.key,
    this.allowMultiple = true,
  });

  final bool allowMultiple;

  static Future<List<String>?> show(BuildContext context, {bool allowMultiple = true}) async {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => InAppPdfSelector(allowMultiple: allowMultiple),
    );
  }

  @override
  ConsumerState<InAppPdfSelector> createState() => _InAppPdfSelectorState();
}

class _InAppPdfSelectorState extends ConsumerState<InAppPdfSelector> {
  final List<String> _selectedPaths = [];

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        if (!widget.allowMultiple) {
          _selectedPaths.clear();
        }
        _selectedPaths.add(path);
      }
    });
  }

  Future<void> _browseOtherApps() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: widget.allowMultiple,
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result.paths.whereType<String>().toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pdfState = ref.watch(pdfLibraryControllerProvider);
    final items = pdfState.items;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text('Select PDF', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_selectedPaths.isNotEmpty)
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selectedPaths),
                      child: Text('Done (${_selectedPaths.length})'),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No PDFs found.',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: items.length,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = _selectedPaths.contains(item.path);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: GestureDetector(
                            onTap: () => _toggleSelection(item.path),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                                    : theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 48,
                                      height: 64,
                                      child: PdfThumbnail(
                                        path: item.path,
                                        isEncrypted: item.isEncrypted,
                                        isCorrupted: item.isCorrupted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            _Badge(label: '${(item.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB', theme: theme),
                                            const SizedBox(width: 6),
                                            if (item.pageCount != null)
                                              _Badge(label: '${item.pageCount}p', theme: theme),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (widget.allowMultiple)
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? Icon(Icons.check, size: 16, color: theme.colorScheme.onPrimary)
                                          : null,
                                    )
                                  else if (isSelected)
                                    Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 28)
                                        .animate().scale(duration: 200.ms, curve: Curves.easeOutBack),
                                ],
                              ),
                            ),
                          ),
                        ).animate(key: ValueKey('sel_${item.path}')).fadeIn(delay: (index > 20 ? 0 : index * 20).ms, duration: 300.ms).slideY(begin: 0.1);
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(HugeIcons.strokeRoundedFolder01),
                        label: const Text('Browse Device Files', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _browseOtherApps,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.theme});
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
    );
  }
}
