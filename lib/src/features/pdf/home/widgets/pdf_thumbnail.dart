import 'package:arcpdf/src/shared/theme/arc_icons.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import 'pdf_thumbnail_cache.dart';
import '../../../settings/settings_controller.dart';

class PdfThumbnail extends ConsumerStatefulWidget {
  const PdfThumbnail(
      {super.key,
      required this.path,
      this.cacheVersion = '',
      this.isEncrypted = false,
      this.isCorrupted = false});
  final String path;
  final String cacheVersion;
  final bool isEncrypted;
  final bool isCorrupted;

  @override
  ConsumerState<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends ConsumerState<PdfThumbnail> {
  (String, String, bool, bool, bool)? _request;
  Future<ui.Image?>? _thumbnail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lowPowerMode =
        ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));

    final request = (
      widget.path,
      widget.cacheVersion,
      lowPowerMode,
      widget.isEncrypted,
      widget.isCorrupted
    );
    if (_request != request) {
      _request = request;
      _thumbnail = widget.isEncrypted || widget.isCorrupted
          ? null
          : PdfThumbnailCache.getThumbnail(widget.path,
              lowPowerMode: lowPowerMode, cacheVersion: widget.cacheVersion);
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
              : _ThumbnailImage(
                  key: ValueKey(_request),
                  future: _thumbnail,
                  reduceMotion: reduceMotion,
                ),
        ),
      ),
    );
  }
}

class _ThumbnailImage extends StatefulWidget {
  const _ThumbnailImage(
      {super.key, required this.future, required this.reduceMotion});

  final Future<ui.Image?>? future;
  final bool reduceMotion;

  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  ui.Image? _image;
  Object? _error;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final image = await widget.future;
      if (!mounted) {
        image?.dispose();
        return;
      }
      setState(() {
        _image = image;
        _complete = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _complete = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null || (_complete && _image == null)) {
      return const _Fallback();
    }
    final image = _image;
    if (image != null) {
      return SizedBox.expand(
        child: RawImage(
          image: image,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    if (widget.reduceMotion) {
      return ColoredBox(color: colors.surfaceContainer);
    }
    return Shimmer.fromColors(
      loop: 1,
      baseColor: colors.surfaceContainer,
      highlightColor: colors.surfaceContainerHighest,
      child: Container(color: colors.surfaceContainer),
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
          ArcIcons.brokenImage,
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
          ArcIcons.pdf,
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
                ArcIcons.lock,
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
