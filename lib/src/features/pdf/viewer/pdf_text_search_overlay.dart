import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfTextSearchOverlay extends StatelessWidget {
  const PdfTextSearchOverlay({
    super.key,
    required this.textSearcher,
    required this.pageRect,
    required this.page,
  });

  final PdfTextSearcher textSearcher;
  final Rect pageRect;
  final PdfPage page;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: textSearcher,
      builder: (context, _) {
        if (!textSearcher.hasMatches) return const SizedBox.shrink();

        final matches = textSearcher.matches;
        final overlays = <Widget>[];

        for (int i = 0; i < matches.length; i++) {
          final match = matches[i];
          if (match.pageNumber != page.pageNumber) continue;

          final isCurrent = textSearcher.currentIndex == i;
          final color = isCurrent ? Colors.orange.withValues(alpha: 0.6) : Colors.yellow.withValues(alpha: 0.4);

          for (final fragment in match.fragments) {
            final bounds = fragment.bounds;
            // bounds is in page coordinate space where 0,0 is top-left usually, but we convert it
            // from page dimensions to the rendered pageRect space.
            final scaledRect = Rect.fromLTRB(
              pageRect.left + bounds.left * (pageRect.width / page.width),
              pageRect.top + bounds.top * (pageRect.height / page.height),
              pageRect.left + bounds.right * (pageRect.width / page.width),
              pageRect.top + bounds.bottom * (pageRect.height / page.height),
            );

            overlays.add(
              Positioned.fromRect(
                rect: scaledRect,
                child: Container(color: color),
              ),
            );
          }
        }

        if (overlays.isEmpty) return const SizedBox.shrink();

        return Stack(children: overlays);
      },
    );
  }
}
