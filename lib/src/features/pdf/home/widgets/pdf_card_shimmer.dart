import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PdfCardShimmer extends StatelessWidget {
  const PdfCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainer;
    final hi = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: hi,
        child: Container(
          height: 136,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}
