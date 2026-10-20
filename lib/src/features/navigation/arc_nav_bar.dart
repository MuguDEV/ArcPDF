import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../settings/settings_controller.dart';
import '../settings/haptic_service.dart';
import 'navigation_controller.dart';
import '../../shared/theme/arc_colors.dart';

const _destinationRadius = BorderRadius.all(Radius.circular(28));

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
    final reduceMotion =
        settings.lowPowerMode || MediaQuery.disableAnimationsOf(context);
    final isBlur = settings.useBlurEffect && !settings.lowPowerMode;
    final isLiquid = settings.useLiquidGlass && !settings.lowPowerMode;
    final double sigma = isLiquid ? 20.0 : 12.0;
    final duration = reduceMotion
        ? Duration.zero
        : Duration(milliseconds: (260 * settings.animationSpeed).round());

    final navBg = theme.colorScheme.surfaceContainerHigh;
    final Color bgColor = navBg.withValues(alpha: isLiquid ? 0.38 : 0.64);

    Widget navContainer = Container(
      height: 48 +
          MediaQuery.textScalerOf(context)
                  .scale(theme.textTheme.labelSmall?.fontSize ?? 11) *
              (theme.textTheme.labelSmall?.height ?? 1.4),
      decoration: BoxDecoration(
        color: isBlur ? bgColor : navBg.withValues(alpha: 0.9),
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
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOutCubic,
              left: (itemWidth * widget.selectedIndex) + 4,
              top: 6,
              bottom: 6,
              width: itemWidth - 8,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: _destinationRadius,
                ),
              ),
            ),

            // Icons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_icons.length, (index) {
                final isSelected = widget.selectedIndex == index;
                final color = isSelected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant;

                final iconWidget = Icon(_icons[index], color: color, size: 24);

                void activate() {
                  if (index != widget.selectedIndex) {
                    ref.read(hapticServiceProvider).selectionClick();
                    ref
                        .read(navigationControllerProvider.notifier)
                        .setIndex(index);
                  }
                }

                return Expanded(
                  child: Semantics(
                    label: _labels[index],
                    button: true,
                    selected: isSelected,
                    onTap: activate,
                    child: Tooltip(
                      message: _labels[index],
                      excludeFromSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: _destinationRadius,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            borderRadius: _destinationRadius,
                            excludeFromSemantics: true,
                            focusColor: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                            onTap: activate,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  iconWidget,
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: Text(
                                      _labels[index],
                                      semanticsLabel: '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: color,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
