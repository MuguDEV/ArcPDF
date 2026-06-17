import 'package:flutter/material.dart';

Future<String?> showRenameDialog(BuildContext context, String currentName) {
  final name = currentName.toLowerCase().endsWith('.pdf')
      ? currentName.substring(0, currentName.length - 4)
      : currentName;
  final controller = TextEditingController(text: name);
  controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);

  return showDialog<String>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.edit_document,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Rename PDF',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  labelText: 'New Name',
                  labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty) {
                        Navigator.of(context).pop(newName);
                      }
                    },
                    child: const Text('Rename'),
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
