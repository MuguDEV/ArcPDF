import 'package:flutter/material.dart';

import 'arc_colors.dart';

/// Shared component colors must follow brightness, not dark-only color tokens.
ThemeData applyArcControlTheme(ThemeData theme) {
  final colors = theme.colorScheme;
  Color foreground(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
          ? colors.onSurface.withValues(alpha: 0.38)
          : states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant;

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(ArcColors.buttonRadius),
  );
  return theme.copyWith(
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surfaceContainerHigh,
      contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: colors.onSurface,
      ),
      actionTextColor: colors.primary,
      disabledActionTextColor: colors.onSurface.withValues(alpha: 0.38),
      closeIconColor: colors.onSurfaceVariant,
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      elevation: 0,
      shape: shape.copyWith(side: BorderSide(color: colors.outline)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(foreground),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.onSurface.withValues(alpha: 0.12);
        }
        return states.contains(WidgetState.selected)
            ? colors.primary
            : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(colors.onPrimary),
      side: BorderSide(color: colors.onSurfaceVariant, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.onSurface.withValues(alpha: 0.38);
        }
        return states.contains(WidgetState.selected)
            ? colors.onPrimary
            : colors.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.onSurface.withValues(alpha: 0.12);
        }
        return states.contains(WidgetState.selected)
            ? colors.primary
            : colors.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.transparent
              : colors.outline),
    ),
    sliderTheme: theme.sliderTheme.copyWith(
      activeTrackColor: colors.primary,
      inactiveTrackColor: colors.surfaceContainerHighest,
      thumbColor: colors.primary,
      overlayColor: colors.primary.withValues(alpha: 0.12),
      valueIndicatorColor: colors.primary,
      valueIndicatorTextStyle:
          theme.textTheme.labelMedium?.copyWith(color: colors.onPrimary),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      circularTrackColor: colors.surfaceContainerHighest,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.primary,
      selectionColor: colors.primary.withValues(alpha: 0.25),
      selectionHandleColor: colors.primary,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle:
          theme.textTheme.bodySmall?.copyWith(color: colors.onInverseSurface),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(shape),
        side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
      ),
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      color: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      textStyle: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      shape: shape,
    ),
  );
}
