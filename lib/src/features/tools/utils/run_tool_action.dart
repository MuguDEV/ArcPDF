import 'package:flutter/material.dart';

export '../tool_action_dialog.dart' show ToolResultKind;

import '../tool_action_dialog.dart';
import '../job_queue.dart';
import '../tool_failure.dart';

/// Own the loading route so completion never pops an unrelated route.
Future<void> runToolAction(
  BuildContext context, {
  required String title,
  required Future<String?> Function() action,
  String Function(String output)? successMessage,
  List<String> Function()? outputFiles,
  ValueNotifier<JobProgress>? progress,
  VoidCallback? onCancel,
  List<String>? inputPaths,
  ToolResultKind resultKind = ToolResultKind.generic,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => progress == null
        ? ToolActionDialog(
            title: title, message: 'Please wait...', isLoading: true)
        : ValueListenableBuilder<JobProgress>(
            valueListenable: progress,
            builder: (_, value, __) => ToolActionDialog(
                  title: title,
                  message: value.stage,
                  progress: value,
                  onCancel: onCancel,
                  isLoading: true,
                )),
  );
  navigator.push(route);
  String? output;
  var cancelled = false;
  ToolFailure? failure;
  try {
    output = await action();
  } on JobCancelledException {
    cancelled = true;
  } catch (error) {
    failure = ToolFailure.from(error);
  } finally {
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }
  if (!context.mounted) return;
  if (cancelled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Operation cancelled')),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => ToolActionDialog(
      title: output == null ? (failure?.title ?? 'Error') : 'Success',
      message: output == null
          ? (failure?.message ??
              'Unable to complete the operation. Check the source files, page selection, and available storage.')
          : (successMessage?.call(output) ?? 'Saved to:\n$output'),
      isLoading: false,
      outputPath: output,
      outputFiles: outputFiles?.call(),
      inputPaths: inputPaths,
      resultKind: resultKind,
    ),
  );
}
