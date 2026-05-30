import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;

import '../../pdf/application/pdf_library_controller.dart';
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
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
                      padding: const EdgeInsets.only(bottom: 100),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = _selectedPaths.contains(item.path);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          leading: SizedBox(
                            width: 40,
                            height: 56,
                            child: PdfThumbnail(
                              path: item.path,
                              isEncrypted: item.isEncrypted,
                              isCorrupted: item.isCorrupted,
                            ),
                          ),
                          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${(item.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB • ${p.dirname(item.path)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          trailing: widget.allowMultiple
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => _toggleSelection(item.path),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                )
                              : isSelected
                                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                                  : const SizedBox(),
                          onTap: () => _toggleSelection(item.path),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(HugeIcons.strokeRoundedFolder01),
                        label: const Text('Browse other apps'),
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
