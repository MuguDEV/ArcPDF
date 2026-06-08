import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ArcProgressIndicator extends StatelessWidget {
  const ArcProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface,
              borderRadius: BorderRadius.circular(8),
            ),
          )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(
            begin: const Offset(0.5, 0.5),
            end: const Offset(1.5, 1.5),
            duration: 600.ms,
            curve: Curves.easeInOutCubicEmphasized,
          )
          .fade(
            begin: 0.5,
            end: 1.0,
            duration: 600.ms,
            curve: Curves.easeInOutCubic,
          ),
        ),
      ),
    );
  }
}
