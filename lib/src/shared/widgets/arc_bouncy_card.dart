import 'package:flutter/material.dart';

class ArcBouncyCard extends StatefulWidget {
  const ArcBouncyCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.95,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;

  @override
  State<ArcBouncyCard> createState() => _ArcBouncyCardState();
}

class _ArcBouncyCardState extends State<ArcBouncyCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (widget.onTap != null || widget.onLongPress != null) {
            setState(() => _isPressed = true);
          }
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap?.call();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
        },
        onLongPress: widget.onLongPress != null ? () {
          setState(() => _isPressed = false);
          widget.onLongPress?.call();
        } : null,
        child: AnimatedScale(
          scale: _isPressed ? widget.scaleDown : 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}
