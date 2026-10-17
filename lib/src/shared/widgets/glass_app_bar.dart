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

    final Color bgColor = isBlur
        ? (isLiquid
            ? (isDark ? const Color(0x33000000) : const Color(0x66FFFFFF))
            : theme.colorScheme.surface.withValues(alpha: isDark ? 0.75 : 0.85))
        : theme.colorScheme.surface;

    return SliverAppBar(
      pinned: pinned,
      backgroundColor: bgColor,
      surfaceTintColor: Colors.transparent, // Prevents Material 3 tint overlay
      flexibleSpace: isBlur
          ? ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: isLiquid ? Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                        width: 0.5, // Subtle bottom rim light
                      ),
                    ) : null,
                  ),
                ),
              ),
            )
          : null,
      title: title,
      actions: actions,
      // Center title properly aligns the typography within the bounds of the navigation bar
      centerTitle: false,
      toolbarHeight: 64.0,
    );
  }
}
