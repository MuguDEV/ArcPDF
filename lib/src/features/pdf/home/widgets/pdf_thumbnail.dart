import 'package:hugeicons/hugeicons.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'pdf_thumbnail_cache.dart';

class PdfThumbnail extends StatelessWidget {
  const PdfThumbnail({super.key, required this.path, this.isEncrypted = false, this.isCorrupted = false});
  final String path;
  final bool isEncrypted;
  final bool isCorrupted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isCorrupted) {
      return _CorruptedFallback(theme: theme);
    }

    final file = File(path);
    if (!file.existsSync()) return const _Fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: isEncrypted
            ? _LockedState(theme: theme)
            : FutureBuilder<Uint8List?>(
                initialData: PdfThumbnailCache.getCached(path),
                future: PdfThumbnailCache.getThumbnail(path),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return Shimmer.fromColors(
                      baseColor: theme.colorScheme.surfaceContainer,
                      highlightColor: theme.colorScheme.surfaceContainerHighest,
                      child: Container(color: theme.colorScheme.surfaceContainer),
                    );
                  }
                  
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                    return const _Fallback();
                  }

                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  );
                },
              ),
      ),
    );
  }
}

class _CorruptedFallback extends StatelessWidget {
  const _CorruptedFallback({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.75, // Default ratio
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: theme.colorScheme.error.withValues(alpha: 0.7),
          size: 32,
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.75, // Default ratio
      child: Center(
        child: Icon(
          HugeIcons.strokeRoundedPdf02,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          size: 28,
        ),
      ),
    );
  }
}

class _LockedState extends StatelessWidget {
  const _LockedState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.75,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          // Lock badge
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Icon(
                HugeIcons.strokeRoundedLockKey,
                size: 24,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
