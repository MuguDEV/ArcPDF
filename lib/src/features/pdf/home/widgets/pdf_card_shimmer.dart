import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../settings/settings_controller.dart';

/// A document-shaped placeholder; movement is bounded and preference-aware.
class PdfCardShimmer extends ConsumerWidget {
  const PdfCardShimmer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context) ||
        ref.watch(settingsControllerProvider.select((s) => s.lowPowerMode));
    Widget line(double width) => Container(
          width: width,
          height: 10,
          decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4)),
        );
    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Container(
            width: 64,
            height: 84,
            decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12))),
        const SizedBox(width: 12),
        Expanded(
            child: LayoutBuilder(
                builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        line(constraints.maxWidth * 0.85),
                        const SizedBox(height: 12),
                        line(constraints.maxWidth * 0.55),
                        const SizedBox(height: 8),
                        line(constraints.maxWidth * 0.7)
                      ],
                    ))),
      ]),
    );
    return ExcludeSemantics(
        child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: reduced
          ? content
          : Shimmer.fromColors(
              loop: 1,
              baseColor: colors.surfaceContainerHigh,
              highlightColor: colors.surfaceContainerLow,
              child: content),
    ));
  }
}
