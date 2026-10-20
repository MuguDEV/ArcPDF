import 'package:flutter/material.dart';

/// Keep transient notices in the same themed, accessible message queue.
abstract final class DynamicIslandNotification {
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final colors = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: duration,
      showCloseIcon: true,
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: colors.onSurface, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(message)),
        ],
      ),
    ));
  }
}
