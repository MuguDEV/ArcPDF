import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/settings_controller.dart';

class GlassSliverAppBar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;
    final isBlur = settings.useBlurEffect && !settings.lowPowerMode;
    final isLiquid = settings.useLiquidGlass && !settings.lowPowerMode;
    final double sigma = isLiquid ? 48.0 : 16.0;

    // Monochrome matching colors
    final Color bgColor = isLiquid
        ? (isDark ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4))
        : theme.colorScheme.surface.withValues(alpha: isBlur ? 0.7 : 1.0);

    // Wrapping inside a SafeArea internally or ensuring SliverAppBar does not draw under status bar content poorly
    return SliverSafeArea(
      top: true,
      bottom: false,
      sliver: SliverAppBar(
        pinned: pinned,
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent, // Prevents Material 3 tint overlay
        flexibleSpace: isBlur
            ? ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: Container(color: Colors.transparent),
                ),
              )
            : null,
        title: title,
        actions: actions,
      ),
    );
  }
}
