import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../application/pdf_library_controller.dart';

class PermissionScreen extends ConsumerWidget {
  const PermissionScreen({super.key, required this.status});
  final StoragePermissionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.read(pdfLibraryControllerProvider.notifier);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status == StoragePermissionStatus.permanentlyDenied
                  ? ArcIcons.blocked
                  : ArcIcons.folderOpen,
              size: 140,
              color: status == StoragePermissionStatus.permanentlyDenied
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 28),
            Text(
              status == StoragePermissionStatus.permanentlyDenied
                  ? 'Access Blocked'
                  : 'Storage Access Needed',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(delay: 150.ms, duration: 400.ms)
                .slideY(begin: 0.1),
            const SizedBox(height: 10),
            Text(
              status == StoragePermissionStatus.permanentlyDenied
                  ? 'Open system settings and enable “All files access” for ArcPDF so it can find PDFs across shared storage.'
                  : 'Allow file access so ArcPDF can find PDF documents across your device. Image and video permissions are not requested.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 250.ms, duration: 400.ms),
            const SizedBox(height: 36),
            if (status == StoragePermissionStatus.permanentlyDenied) ...[
              FilledButton.icon(
                onPressed: () async {
                  await Permission.manageExternalStorage.request();
                  await ctrl.refresh(requestPermission: false);
                },
                icon: const Icon(ArcIcons.settings),
                label: const Text('Open Settings'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
              ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1),
            ] else ...[
              FilledButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Storage Permission Needed'),
                      content: const Text(
                          'Android will open the “All files access” screen. Enable ArcPDF there to build your local PDF library. ArcPDF does not upload your files.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            ctrl.refresh(requestPermission: true);
                          },
                          child: const Text('Grant Access'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(ArcIcons.folderOpen),
                label: const Text('Grant Access'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
              ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open App Settings'),
              ).animate().fadeIn(delay: 450.ms),
            ],
          ],
        ),
      ),
    );
  }
}
