import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ArcEmptyState extends StatelessWidget {
  const ArcEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.animated = false,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final bool animated;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    Widget iconWidget = Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Icon(icon, size: 40, color: color),
    );

    if (animated) {
      iconWidget = iconWidget
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.96, end: 1.0, duration: 2000.ms, curve: Curves.easeInOutCubicEmphasized);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget.animate().scale(
                  begin: const Offset(0.0, 0.0),
                  duration: 800.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 22),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            )
            .animate()
            .fadeIn(delay: 100.ms, duration: 400.ms)
            .slideY(begin: 0.2, curve: Curves.easeInOutCubicEmphasized, duration: 600.ms),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            )
            .animate()
            .fadeIn(delay: 150.ms, duration: 400.ms)
            .slideY(begin: 0.2, curve: Curves.easeInOutCubicEmphasized, duration: 600.ms),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: action,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  minimumSize: const Size(160, 48),
                ),
                child: Text(actionLabel!),
              )
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideY(begin: 0.2, curve: Curves.easeInOutCubicEmphasized, duration: 600.ms),
            ],
          ],
        ),
      ),
    );
  }
}

// Legacy shim so old code referencing EmptyState still compiles
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ArcEmptyState(
      icon: Icons.insert_drive_file_outlined,
      title: title,
      subtitle: subtitle,
    );
  }
}
