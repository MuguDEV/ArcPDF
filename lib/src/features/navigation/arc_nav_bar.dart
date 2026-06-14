import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../settings/settings_controller.dart';
import '../settings/haptic_service.dart';
import 'navigation_controller.dart';

class ArcNavBar extends ConsumerStatefulWidget {
  const ArcNavBar({super.key, required this.selectedIndex});
  final int selectedIndex;

  @override
  ConsumerState<ArcNavBar> createState() => _ArcNavBarState();
}

class _ArcNavBarState extends ConsumerState<ArcNavBar> {
  final List<IconData> _icons = [
    HugeIcons.strokeRoundedHome01,
    HugeIcons.strokeRoundedFavourite,
    HugeIcons.strokeRoundedClock01,
    HugeIcons.strokeRoundedDashboardSquare01,
    HugeIcons.strokeRoundedSettings01,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final settings = ref.watch(settingsControllerProvider);
    final isBlur = settings.useBlurEffect;
    final isLiquid = settings.useLiquidGlass;
    final double sigma = isLiquid ? 48.0 : 24.0;

    final navBg = isDark ? const Color(0xFF1C1C1C) : const Color(0xFFFCFCFC);
    final Color bgColor = isLiquid
        ? (isDark ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4))
        : navBg.withValues(alpha: isDark ? 0.75 : 0.85);

    Widget navContainer = Container(
      height: 64,
      decoration: BoxDecoration(
        color: isBlur ? bgColor : navBg,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Fluid Pill Indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack, // Bouncy slide
            left: _calculateIndicatorOffset(context),
            top: 10,
            bottom: 10,
            width: _calculateItemWidth(context),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Icons Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_icons.length, (index) {
              final isSelected = widget.selectedIndex == index;
              final color = isSelected
                  ? (isDark ? Colors.white : theme.colorScheme.primary)
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

              Widget iconWidget = Icon(_icons[index], color: color, size: 24);

              if (isSelected) {
                // Jelly squash and stretch effect when selected
                iconWidget = iconWidget.animate(key: ValueKey(index)).scaleX(
                  begin: 1.3, end: 1.0, duration: 400.ms, curve: Curves.elasticOut
                ).scaleY(
                  begin: 0.7, end: 1.0, duration: 400.ms, curve: Curves.elasticOut
                );
              } else {
                 iconWidget = iconWidget.animate().scale(begin: const Offset(0.9, 0.9));
              }

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (index != widget.selectedIndex) {
                      ref.read(hapticServiceProvider).selectionClick();
                      ref.read(navigationControllerProvider.notifier).setIndex(index);
                    }
                  },
                  child: Center(child: iconWidget),
                ),
              );
            }),
          ),
        ],
      ),
    );

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(40, 0, 40, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: isBlur ? BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: navContainer,
        ) : navContainer,
      ),
    );
  }

  double _calculateItemWidth(BuildContext context) {
    // 80 padding (40 left + 40 right) from SafeArea
    final availableWidth = MediaQuery.of(context).size.width - 80;
    return availableWidth / _icons.length;
  }

  double _calculateIndicatorOffset(BuildContext context) {
    return _calculateItemWidth(context) * widget.selectedIndex;
  }
}
