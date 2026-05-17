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
        title: const Text('Rename PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'New Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
