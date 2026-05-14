import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/annotation_repository.dart';
import '../domain/pdf_annotation.dart';
import '../domain/pdf_file_item.dart';

class PdfAnnotationOverlay extends ConsumerStatefulWidget {
  const PdfAnnotationOverlay({
    super.key,
    required this.item,
    required this.pageRect,
    required this.page,
    this.unsavedHighlights = const [],
  });

  final PdfFileItem item;
  final Rect pageRect;
  final PdfPage page;
  final List<PdfAnnotation> unsavedHighlights;

  @override
  ConsumerState<PdfAnnotationOverlay> createState() => _PdfAnnotationOverlayState();
}

class _PdfAnnotationOverlayState extends ConsumerState<PdfAnnotationOverlay> {
  List<PdfAnnotation> _annotations = [];

  @override
  void initState() {
    super.initState();
    _loadAnnotations();
  }

  @override
  void didUpdateWidget(covariant PdfAnnotationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path || oldWidget.page.pageNumber != widget.page.pageNumber) {
      _loadAnnotations();
    } else if (oldWidget.unsavedHighlights.length != widget.unsavedHighlights.length) {
      // Re-load to catch new annotations that were saved and moved out of unsavedHighlights
      _loadAnnotations();
    }
  }

  void _loadAnnotations() {
    final repo = ref.read(annotationRepositoryProvider);
    final annotations = repo.getAnnotationsForPage(widget.item.path, widget.page.pageNumber);
    if (_annotations.length != annotations.length) {
      setState(() {
        _annotations = annotations;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allAnnotations = [
      ..._annotations,
      ...widget.unsavedHighlights.where((a) => a.pageNumber == widget.page.pageNumber),
    ];

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
