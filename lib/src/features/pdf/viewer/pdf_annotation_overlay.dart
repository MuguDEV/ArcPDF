import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/annotation_repository.dart';
import '../domain/pdf_file_item.dart';

class PdfAnnotationOverlay extends ConsumerStatefulWidget {
  const PdfAnnotationOverlay({
    super.key,
    required this.item,
    required this.pageRect,
    required this.page,
  });

  final PdfFileItem item;
  final Rect pageRect;
  final PdfPage page;

  @override
  ConsumerState<PdfAnnotationOverlay> createState() => _PdfAnnotationOverlayState();
}

class _PdfAnnotationOverlayState extends ConsumerState<PdfAnnotationOverlay> {
  @override
  Widget build(BuildContext context) {
    // Watch for updates from the repository (ChangeNotifier)
    final repo = ref.watch(annotationRepositoryProvider);
    final allAnnotations = repo.getAnnotationsForPage(widget.item.path, widget.page.pageNumber);

    if (allAnnotations.isEmpty) return const SizedBox.shrink();

    final overlays = <Widget>[];

    for (final annotation in allAnnotations) {
      if (annotation.bounds.isEmpty || annotation.bounds.length % 4 != 0) continue;

      for (int i = 0; i < annotation.bounds.length; i += 4) {
        final boundsRect = Rect.fromLTRB(
          annotation.bounds[i],
          annotation.bounds[i + 1],
          annotation.bounds[i + 2],
          annotation.bounds[i + 3],
        );

        final scaledRect = Rect.fromLTRB(
          widget.pageRect.left + boundsRect.left * (widget.pageRect.width / widget.page.width),
          widget.pageRect.top + boundsRect.top * (widget.pageRect.height / widget.page.height),
          widget.pageRect.left + boundsRect.right * (widget.pageRect.width / widget.page.width),
          widget.pageRect.top + boundsRect.bottom * (widget.pageRect.height / widget.page.height),
        );

        if (annotation.type == 'highlight') {
          overlays.add(
            Positioned.fromRect(
              rect: scaledRect,
              child: Container(
                color: Color(annotation.color).withValues(alpha: 0.4),
              ),
            ),
          );
        }
      }
    }

    return Stack(children: overlays);
  }
}
