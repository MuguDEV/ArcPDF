import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/pdf_library_controller.dart';
import '../../domain/pdf_file_item.dart';
import '../../../vault/vault_controller.dart';
import 'package:hugeicons/hugeicons.dart';

void showPdfBottomSheet(BuildContext context, WidgetRef ref, PdfFileItem item) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
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
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.item.name,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          Text('Tags', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...tags.map((tag) => InputChip(
                    label: Text(tag),
                    onDeleted: () {
                      ctrl.removeTag(widget.item, tag);
                    },
                  )),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagController,
                  decoration: InputDecoration(
                    hintText: 'Add new tag...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      ctrl.addTag(widget.item, val.trim());
                      _tagController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () {
                  if (_tagController.text.trim().isNotEmpty) {
                    ctrl.addTag(widget.item, _tagController.text.trim());
                    _tagController.clear();
                  }
                },
                icon: const Icon(Icons.add),
              )
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: Icon(HugeIcons.strokeRoundedFolderSecurity, color: theme.colorScheme.error),
            title: const Text('Move to Secure Vault'),
            contentPadding: EdgeInsets.zero,
            onTap: () async {
              final success = await ref.read(vaultControllerProvider.notifier).moveToVault(widget.item);
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File moved to Secure Vault')),
                );
                Navigator.pop(context);
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to move to vault')),
                );
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
