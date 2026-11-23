import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/arc_icons.dart';
import '../settings/haptic_service.dart';
import '../settings/settings_controller.dart';
import 'navigation_controller.dart';

/// A compact floating dock over an otherwise transparent navigation area.
class ArcNavBar extends ConsumerWidget {
  const ArcNavBar({super.key, required this.selectedIndex});
  final int selectedIndex;
  static const _icons = [
    ArcIcons.home,
    ArcIcons.favorite,
    ArcIcons.history,
    ArcIcons.tools,
    ArcIcons.settings
  ];
  static const _labels = ['Home', 'Favorites', 'Recent', 'Tools', 'Settings'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final settings = ref.watch(settingsControllerProvider);
    final reduced =
        settings.lowPowerMode || MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : Duration(milliseconds: (200 * settings.animationSpeed).round());
    const itemRadius = BorderRadius.all(Radius.circular(16));
    const dockRadius = BorderRadius.all(Radius.circular(28));
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(22, 6, 22, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            key: const ValueKey('floating-navigation-dock'),
            // Keep the region around the dock completely transparent while a
            // restrained translucent surface protects icon/text contrast over
            // scrolling documents.
            color: colors.surfaceContainerHigh.withValues(alpha: 0.90),
            elevation: 2,
            shadowColor: colors.shadow.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: dockRadius,
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: LayoutBuilder(builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / _labels.length;
                var labelHeight = 0.0;
                for (final label in _labels) {
                  final painter = TextPainter(
                    text: TextSpan(
                        text: label, style: theme.textTheme.labelSmall),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(maxWidth: itemWidth - 4);
                  if (painter.height > labelHeight) {
                    labelHeight = painter.height;
                  }
                  painter.dispose();
                }
                final visualIndex =
                    Directionality.of(context) == TextDirection.rtl
                        ? _labels.length - 1 - selectedIndex
                        : selectedIndex;
                return SizedBox(
                  height: 42 + labelHeight,
                  child: Stack(children: [
                    AnimatedPositioned(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        left: itemWidth * visualIndex + (itemWidth - 46) / 2,
                        top: 0,
                        width: 46,
                        height: 40,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: colors.onSurface.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18)))),
                    Row(
                        children: List.generate(_labels.length, (index) {
                      final selected = index == selectedIndex;
                      void activate() {
                        if (!selected) {
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
                        selected: selected,
                        onTap: activate,
                        child: Tooltip(
                          message: _labels[index],
                          excludeFromSemantics: true,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: itemRadius,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              borderRadius: itemRadius,
                              excludeFromSemantics: true,
                              onTap: activate,
                              child: ExcludeSemantics(
                                  child: Column(children: [
                                SizedBox(
                                    height: 40,
                                    child: Center(
                                        child: Icon(_icons[index],
                                            size: 22,
                                            color: selected
                                                ? colors.onSurface
                                                : colors.onSurfaceVariant))),
                                const SizedBox(height: 2),
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    child: Text(_labels[index],
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                // The accent indicator only
                                                // sits behind the icon. Keep
                                                // the label legible against
                                                // the transparent dock/body.
                                                color: selected
                                                    ? colors.onSurface
                                                    : colors
                                                        .onSurfaceVariant))),
                              ])),
                            ),
                          ),
                        ),
                      ));
                    })),
                  ]),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
