import 'package:flutter/material.dart';

class GlassSliverAppBar extends StatelessWidget {
  final Widget title;
  final List<Widget>? actions;
  final bool pinned;

  const GlassSliverAppBar({
    super.key,
    required this.title,
    this.actions,
    this.pinned = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SliverAppBar(
      pinned: pinned,
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      title: title,
      titleTextStyle: theme.textTheme.headlineMedium
          ?.copyWith(color: theme.colorScheme.onSurface),
      actions: actions,
      centerTitle: false,
      toolbarHeight:
          64.0 + (MediaQuery.textScalerOf(context).scale(20) - 20).clamp(0, 48),
    );
  }
}
