import 'package:flutter/material.dart';
import '../../application/pdf_error_handler.dart';
import '../../../settings/haptic_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../application/pdf_library_controller.dart';
import '../../application/open_tabs_provider.dart';
import '../../domain/pdf_file_item.dart';
import '../../../vault/vault_controller.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../tools/pages/rearrange_pages_page.dart';
import '../../../tools/pages/metadata_editor_page.dart';
import '../../../../shared/utils/glass_bottom_sheet.dart';

void showPdfBottomSheet(BuildContext context, WidgetRef ref, PdfFileItem item) {
  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PdfBottomSheet(item: item),
  );
}

class _PdfBottomSheet extends ConsumerStatefulWidget {
  const _PdfBottomSheet({required this.item});
  final PdfFileItem item;

  @override
  ConsumerState<_PdfBottomSheet> createState() => _PdfBottomSheetState();
}

class _PdfBottomSheetState extends ConsumerState<_PdfBottomSheet> {
  final _tagController = TextEditingController();
  bool _isBusy = false;

  void _closeOpenTab() {
    final tabs = ref.read(openTabsProvider).tabs;
    final index = tabs.indexWhere((tab) => tab.path == widget.item.path);
    if (index >= 0) ref.read(openTabsProvider.notifier).closeTab(index);
  }

  Future<void> _moveToVault() async {
    if (_isBusy) return;
    final vault = ref.read(vaultControllerProvider.notifier);
    final library = ref.read(pdfLibraryControllerProvider.notifier);
    setState(() => _isBusy = true);
    try {
      final success = await vault.moveToVault(widget.item);
      if (!success) {
        throw StateError('The file could not be moved to the vault.');
      }
      // The source is gone; remove its library metadata without deleting a
      // second file or leaving favorite/recent entries pointing at plaintext.
      await library.removeMissingFile(widget.item);
      if (!mounted) return;
      _closeOpenTab();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File moved to Secure Vault')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        PdfErrorHandler.show(context, error,
            contextMessage: 'Failed to move to vault');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = ref.watch(pdfLibraryControllerProvider.notifier);
    final tags = ref.watch(pdfLibraryControllerProvider
        .select((s) => s.tags[widget.item.path] ?? []));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: IgnorePointer(
        ignoring: _isBusy,
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
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
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          HugeIcons.strokeRoundedPdf02,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _fileSize(widget.item.sizeBytes),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'TAGS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...tags.map((tag) => InputChip(
                              label: Text(tag),
                              onDeleted: () {
                                ref
                                    .read(hapticServiceProvider)
                                    .selectionClick();
                                ctrl.removeTag(widget.item, tag);
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          decoration: InputDecoration(
                            hintText: 'Add new tag...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor:
                                theme.colorScheme.surfaceContainerHighest,
                            prefixIcon: const Icon(HugeIcons.strokeRoundedTag01,
                                size: 20),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              ref.read(hapticServiceProvider).selectionClick();
                              ctrl.addTag(widget.item, val.trim());
                              _tagController.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        onPressed: () {
                          if (_tagController.text.trim().isNotEmpty) {
                            ref.read(hapticServiceProvider).selectionClick();
                            ctrl.addTag(
                                widget.item, _tagController.text.trim());
                            _tagController.clear();
                          }
                        },
                        tooltip: 'Add tag',
                        icon: const Icon(Icons.add),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_isBusy) const LinearProgressIndicator(),
                Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                _ActionTile(
                  icon: HugeIcons.strokeRoundedGridView,
                  title: 'Rearrange / Delete Pages',
                  color: theme.colorScheme.onSurface,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          RearrangePagesPage(initialFile: widget.item),
                    ));
                  },
                ),
                _ActionTile(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  title: 'Edit Metadata',
                  color: theme.colorScheme.onSurface,
                  onTap: () {
                    ref.read(hapticServiceProvider).lightImpact();
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          MetadataEditorPage(initialFile: widget.item),
                    ));
                  },
                ),
                _ActionTile(
                  icon: HugeIcons.strokeRoundedFolderSecurity,
                  title: 'Move to Secure Vault',
                  color: theme.colorScheme.primary,
                  onTap: _moveToVault,
                ),
                _ActionTile(
                  icon: HugeIcons.strokeRoundedDelete01,
                  title: 'Delete File',
                  color: theme.colorScheme.error,
                  onTap: () async {
                    ref.read(hapticServiceProvider).mediumImpact();
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return Dialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHigh,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.errorContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    HugeIcons.strokeRoundedDelete01,
                                    size: 32,
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Delete File',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Are you sure you want to delete "${widget.item.name}"? This action cannot be undone.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 24),
                                OverflowBar(
                                  alignment: MainAxisAlignment.end,
                                  overflowAlignment: OverflowBarAlignment.end,
                                  overflowSpacing: 8,
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        backgroundColor:
                                            theme.colorScheme.error,
                                        foregroundColor:
                                            theme.colorScheme.onError,
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );

                    if (confirm != true || !mounted || _isBusy) return;
                    setState(() => _isBusy = true);
                    try {
                      final success = await ctrl.deleteFile(widget.item);
                      if (!mounted || !context.mounted) return;
                      if (!success) {
                        throw StateError('The file could not be deleted.');
                      }
                      _closeOpenTab();
                      ref.read(hapticServiceProvider).selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File deleted')),
                      );
                      Navigator.pop(context);
                    } catch (error) {
                      if (mounted && context.mounted) {
                        PdfErrorHandler.show(context, error,
                            contextMessage: 'Failed to delete file');
                      }
                    } finally {
                      if (mounted) setState(() => _isBusy = false);
                    }
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.1, duration: 250.ms, curve: Curves.easeOutQuad);
  }

  String _fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
