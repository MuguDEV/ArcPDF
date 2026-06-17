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

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedScale(
      scale: _isPressed ? widget.scaleDown : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    if (widget.tooltip != null) {
      content = Tooltip(
        message: widget.tooltip!,
        child: content,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: widget.onPressed != null ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: widget.onPressed != null ? (_) {
        setState(() => _isPressed = false);
        widget.onPressed!();
      } : null,
      onTapCancel: widget.onPressed != null ? () => setState(() => _isPressed = false) : null,
      child: content,
    );
  }
}
