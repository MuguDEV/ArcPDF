import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../application/pdf_library_controller.dart';
import '../../domain/pdf_file_item.dart';
import '../../../vault/vault_controller.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../tools/pages/rearrange_pages_page.dart';

void showPdfBottomSheet(BuildContext context, WidgetRef ref, PdfFileItem item) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
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

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = ref.watch(pdfLibraryControllerProvider.notifier);
    final tags = ref.watch(pdfLibraryControllerProvider.select((s) => s.tags[widget.item.path] ?? []));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                            HapticFeedback.selectionClick();
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        prefixIcon: const Icon(HugeIcons.strokeRoundedTag01, size: 20),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          HapticFeedback.selectionClick();
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
                        HapticFeedback.selectionClick();
                        ctrl.addTag(widget.item, _tagController.text.trim());
                        _tagController.clear();
                      }
                    },
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            _ActionTile(
              icon: HugeIcons.strokeRoundedGridView,
              title: 'Rearrange / Delete Pages',
              color: theme.colorScheme.onSurface,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RearrangePagesPage()));
              },
            ),
            _ActionTile(
              icon: HugeIcons.strokeRoundedFolderSecurity,
              title: 'Move to Secure Vault',
              color: theme.colorScheme.primary,
              onTap: () async {
              HapticFeedback.mediumImpact();
              final success = await ref.read(vaultControllerProvider.notifier).moveToVault(widget.item);
              if (success && context.mounted) {
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File moved to Secure Vault')),
                );
                Navigator.pop(context);
              } else if (context.mounted) {
                HapticFeedback.heavyImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to move to vault')),
                );
                Navigator.pop(context);
              }
            },
          ),
            _ActionTile(
              icon: HugeIcons.strokeRoundedDelete01,
              title: 'Delete File',
              color: theme.colorScheme.error,
              onTap: () async {
                HapticFeedback.mediumImpact();
                final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete File'),
                  content: Text('Are you sure you want to delete "${widget.item.name}"? This action cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

                if (confirm == true) {
                  try {
                    final file = File(widget.item.path);
                    if (await file.exists()) {
                      await file.delete();
                      ref.read(pdfLibraryControllerProvider.notifier).refresh();
                      HapticFeedback.selectionClick();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted')));
                        Navigator.pop(context);
                      }
                    }
                  } catch (e) {
                    HapticFeedback.heavyImpact();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete file')));
                      Navigator.pop(context);
                    }
                  }
                }
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.1, duration: 250.ms, curve: Curves.easeOutQuad);
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
