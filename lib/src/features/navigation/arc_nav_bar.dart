import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../settings/settings_controller.dart';
import '../settings/haptic_service.dart';
import 'navigation_controller.dart';
import '../../shared/theme/arc_colors.dart';

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
  final List<String> _labels = const [
    'Home',
    'Favorites',
    'Recent',
    'Tools',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final settings = ref.watch(settingsControllerProvider);
    final isBlur = settings.useBlurEffect;
    final isLiquid = settings.useLiquidGlass;
    final double sigma = isLiquid ? 48.0 : 24.0;

    final navBg = isDark ? ArcColors.surfaceToken : ArcColors.textPrimary;
    final Color bgColor = isLiquid
        ? (isDark
            ? Colors.black.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.4))
        : navBg.withValues(alpha: isDark ? 0.75 : 0.85);

    Widget navContainer = Container(
      height: 64,
      decoration: BoxDecoration(
        color: isBlur ? bgColor : navBg,
        borderRadius: BorderRadius.circular(ArcColors.sheetRadius),
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
      child: LayoutBuilder(builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / _icons.length;

        return Stack(
          children: [
            // Fluid Pill Indicator
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack, // Bouncy slide
              left: (itemWidth * widget.selectedIndex) + 12,
              top: 10,
              bottom: 10,
              width: itemWidth - 24,
              child: Container(
                decoration: BoxDecoration(
                  color: ArcColors.active.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(ArcColors.buttonRadius),
                ),
              ),
            ),

            // Icons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_icons.length, (index) {
                final isSelected = widget.selectedIndex == index;
                final color = isSelected
                    ? ArcColors.active
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

                Widget iconWidget = Icon(_icons[index], color: color, size: 24);

                if (isSelected) {
                  // Jelly squash and stretch effect when selected
                  iconWidget = iconWidget
                      .animate(key: ValueKey(index))
                      .scaleX(
                          begin: 1.4,
                          end: 1.0,
                          duration: 500.ms,
                          curve: Curves.elasticOut)
                      .scaleY(
                          begin: 0.6,
                          end: 1.0,
                          duration: 500.ms,
                          curve: Curves.elasticOut);
                } else {
                  iconWidget =
                      iconWidget.animate().scale(begin: const Offset(0.9, 0.9));
                }

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (index != widget.selectedIndex) {
                        ref.read(hapticServiceProvider).selectionClick();
                        ref
                            .read(navigationControllerProvider.notifier)
                            .setIndex(index);
                      }
                    },
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          iconWidget,
                          Text(
                            _labels[index],
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      }),
    );

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ArcColors.sheetRadius),
        child: isBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: navContainer,
              )
            : navContainer,
      ),
    );
  }
}
