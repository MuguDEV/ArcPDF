import 'package:flutter/material.dart';

class ToolActionDialog extends StatelessWidget {
  const ToolActionDialog({
    super.key,
    required this.title,
    required this.message,
    required this.isLoading,
  });

  final String title;
  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(title),
      content: Row(
        children: [
          if (isLoading) const CircularProgressIndicator(),
          if (isLoading) const SizedBox(width: 16),
          Expanded(child: Text(message)),
        ],
      ),
      actions: [
        if (!isLoading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
      ],
    );
  }
}
