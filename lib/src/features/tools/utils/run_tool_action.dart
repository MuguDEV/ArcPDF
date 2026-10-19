import 'package:flutter/material.dart';

import '../tool_action_dialog.dart';

/// Own the loading route so completion never pops an unrelated route.
Future<void> runToolAction(
  BuildContext context, {
  required String title,
  required Future<String?> Function() action,
  String Function(String output)? successMessage,
  List<String> Function()? outputFiles,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ToolActionDialog(
        title: title, message: 'Please wait...', isLoading: true),
  );
  navigator.push(route);
  String? output;
  try {
    output = await action();
  } catch (_) {
    // Directory, permission, and plugin failures must also dismiss loading.
  } finally {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => ToolActionDialog(
      title: output == null ? 'Error' : 'Success',
      message: output == null
          ? 'Unable to complete the operation. Check the source files, page selection, and available storage.'
          : (successMessage?.call(output) ?? 'Saved to:\n$output'),
      isLoading: false,
      outputPath: output,
      outputFiles: outputFiles?.call(),
    ),
  );
}
