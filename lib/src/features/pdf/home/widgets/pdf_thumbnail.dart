import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import 'pdf_thumbnail_cache.dart';
import '../../../settings/settings_controller.dart';

class PdfThumbnail extends ConsumerStatefulWidget {
  const PdfThumbnail(
      {super.key,
      required this.path,
      this.isEncrypted = false,
      this.isCorrupted = false});
  final String path;
  final bool isEncrypted;
  final bool isCorrupted;

  @override
  ConsumerState<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends ConsumerState<PdfThumbnail> {
  (String, bool, bool, bool)? _request;
  Future<ui.Image?>? _thumbnail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lowPowerMode =
        ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));

    final request =
        (widget.path, lowPowerMode, widget.isEncrypted, widget.isCorrupted);
    if (_request != request) {
      _request = request;
      _thumbnail = widget.isEncrypted || widget.isCorrupted
          ? null
          : PdfThumbnailCache.getThumbnail(widget.path,
              lowPowerMode: lowPowerMode);
    }
    final reduceMotion =
        lowPowerMode || MediaQuery.disableAnimationsOf(context);

    if (widget.isCorrupted) {
      return _CorruptedFallback(theme: theme);
    }

    return SizedBox(
      width: 52,
      height: 72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: widget.isEncrypted
              ? _LockedState(theme: theme)
              : FutureBuilder<ui.Image?>(
                  key: ValueKey(_request),
                  initialData: PdfThumbnailCache.getCached(widget.path,
                      lowPowerMode: lowPowerMode),
                  future: _thumbnail,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      if (reduceMotion) {
                        return ColoredBox(
                            color: theme.colorScheme.surfaceContainer);
                      }
                      return Shimmer.fromColors(
                        // Do not keep ticking while slow I/O or queued work waits.
                        loop: 1,
                        baseColor: theme.colorScheme.surfaceContainer,
                        highlightColor:
                            theme.colorScheme.surfaceContainerHighest,
                        child: Container(
                            color: theme.colorScheme.surfaceContainer),
                      );
                    }

                    if (snapshot.hasError ||
                        !snapshot.hasData ||
                        snapshot.data == null) {
                      return const _Fallback();
                    }

                    return SizedBox.expand(
                      child: RawImage(
                        image: snapshot.data!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    );
                  },
                ),
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
    return SizedBox(
      width: 52,
      height: 72,
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: theme.colorScheme.error.withValues(alpha: 0.7),
          size: 28,
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 72,
      child: Center(
        child: Icon(
          HugeIcons.strokeRoundedPdf02,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.5),
          size: 24,
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
    return SizedBox(
      width: 52,
      height: 72,
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
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
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
