import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum PdfErrorCategory { userError, broken, unexpected }

class PdfErrorHandler {
  static PdfErrorCategory _classify(Object error) {
    final str = error.toString().toLowerCase();
    if (str.contains('password') || str.contains('invalid page')) {
      return PdfErrorCategory.userError;
    }
    if (str.contains('corrupt') ||
        str.contains('format') ||
        str.contains('invalid pdf') ||
        str.contains('failed to load')) {
      return PdfErrorCategory.broken;
    }
    return PdfErrorCategory.unexpected;
  }

  static void show(BuildContext context, Object error,
      {String? contextMessage}) {
    final category = _classify(error);
    final String title;
    final String message;
    final IconData icon;

    switch (category) {
      case PdfErrorCategory.userError:
        title = 'User Error';
        message = contextMessage ?? 'Invalid input or wrong password.';
        icon = HugeIcons.strokeRoundedAlert01;
        break;
      case PdfErrorCategory.broken:
        title = 'Corrupted PDF';
        message = contextMessage ?? 'The file is broken or malformed.';
        icon = HugeIcons.strokeRoundedFile01;
        break;
      case PdfErrorCategory.unexpected:
        title = 'Unexpected Error';
        message = contextMessage ?? 'Something went wrong. Please try again.';
        icon = HugeIcons.strokeRoundedInformationCircle;
        if (kDebugMode) {
          debugPrint('PdfErrorHandler: $error');
        }
        break;
    }

    // Consistent presentation using Dialog as per app guidelines
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
