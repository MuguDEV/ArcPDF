import 'package:flutter/material.dart';
import '../../../shared/theme/arc_icons.dart';
import '../../../shared/theme/arc_theme.dart';

/// Natural-height rows at enlarged text; a compact toolbox on regular phones.
class ToolCollection extends StatelessWidget {
  const ToolCollection({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
        final columns = largeText || constraints.maxWidth < 330
            ? 1
            : constraints.maxWidth >= 700
                ? 3
                : 2;
        return Column(children: [
          for (var row = 0; row < children.length; row += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IntrinsicHeight(
                  child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0;
                      col < columns && row + col < children.length;
                      col++) ...[
                    if (col > 0) const SizedBox(width: 12),
                    Expanded(child: children[row + col]),
                  ],
                ],
              )),
            ),
        ]);
      });
}

class ToolCard extends StatelessWidget {
  const ToolCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon,
      this.horizontal = false,
      required this.onTap});
  final String title;
  final String subtitle;
  final IconData icon;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
    final badge = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 22, color: colors.onSurface));
    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
        ]);
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: ArcContrast.isHigh(context)
              ? BorderSide(color: colors.outline, width: 2)
              : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: horizontal && !largeText
              ? Row(children: [
                  badge,
                  const SizedBox(width: 16),
                  Expanded(child: content),
                  const SizedBox(width: 8),
                  Icon(ArcIcons.forward,
                      size: 18, color: colors.onSurfaceVariant)
                ])
              : largeText
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [badge, const SizedBox(height: 12), content])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          Row(children: [
                            badge,
                            const Spacer(),
                            Icon(ArcIcons.forward,
                                size: 18, color: colors.onSurfaceVariant)
                          ]),
                          const SizedBox(height: 16),
                          content
                        ]),
        ),
      ),
    );
  }
}
