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
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container with subtle glow
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                color: isDark ? const Color(0xFF252525) : theme.colorScheme.surfaceContainerHigh,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: Icon(
                status == StoragePermissionStatus.permanentlyDenied
                    ? Icons.folder_off_rounded
                    : Icons.folder_open_rounded,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
                .animate()
                .scale(begin: const Offset(0.8, 0.8), duration: 600.ms, curve: Curves.easeOutBack)
                .fadeIn(duration: 400.ms),

            const SizedBox(height: 28),

            Text(
              status == StoragePermissionStatus.permanentlyDenied
                  ? 'Access Blocked'
                  : 'Storage Access Needed',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 150.ms, duration: 400.ms).slideY(begin: 0.1),

            const SizedBox(height: 10),

            Text(
              status == StoragePermissionStatus.permanentlyDenied
                  ? 'ArcPDF needs access to your files to display PDFs. Please open Settings and grant storage permission.'
                  : 'ArcPDF needs permission to scan your device storage for PDF files.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 250.ms, duration: 400.ms),

            const SizedBox(height: 36),

            if (status == StoragePermissionStatus.permanentlyDenied) ...[
              FilledButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Open Settings'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
              ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1),
            ] else ...[
              FilledButton.icon(
                onPressed: ctrl.refresh,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Grant Access'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
