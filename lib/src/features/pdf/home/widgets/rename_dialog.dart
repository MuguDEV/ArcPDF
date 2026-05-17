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
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        title: Row(
          children: [
            Icon(Icons.edit_document, color: theme.colorScheme.onSurface),
            const SizedBox(width: 12),
            const Text('Rename PDF'),
          ],
        ),
        content: TextField(
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
              borderSide: BorderSide(color: theme.colorScheme.onSurface),
            ),
            labelText: 'New Name',
            labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.onSurface,
              foregroundColor: theme.colorScheme.surface,
              elevation: 0,
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
      );
    },
  );
}
