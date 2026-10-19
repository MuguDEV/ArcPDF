import 'package:flutter/material.dart';

class ArcBouncyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double scaleDown;

  const ArcBouncyButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.scaleDown = 0.8,
  });

  @override
  State<ArcBouncyButton> createState() => _ArcBouncyButtonState();
}

class _ArcBouncyButtonState extends State<ArcBouncyButton> {
  bool _isPressed = false;
  bool _hasFocus = false;

  @override
  void didUpdateWidget(ArcBouncyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) {
      _isPressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);
    const borderRadius = BorderRadius.all(Radius.circular(8));

    Widget content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onPressed,
        canRequestFocus: enabled,
        borderRadius: borderRadius,
        splashFactory: reduceMotion ? NoSplash.splashFactory : null,
        onFocusChange: (value) => setState(() => _hasFocus = value),
        onHighlightChanged: (value) {
          if (widget.onPressed != null && _isPressed != value) {
            setState(() => _isPressed = value);
          }
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: enabled && _hasFocus
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: AnimatedScale(
                scale: enabled && _isPressed && !reduceMotion
                    ? widget.scaleDown
                    : 1.0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                child: Opacity(
                  opacity: enabled ? 1 : 0.38,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      content = Tooltip(
        message: widget.tooltip!,
        excludeFromSemantics: true,
        child: content,
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: content,
    );
  }
}
