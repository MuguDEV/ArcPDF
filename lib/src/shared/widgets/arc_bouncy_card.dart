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
  Offset _localOffset = Offset.zero;
  final GlobalKey _key = GlobalKey();

  void _updateTilt(Offset localPosition) {
    if (_key.currentContext == null) return;
    final size = _key.currentContext!.size;
    if (size != null) {
      setState(() {
        // Map position to a -1.0 to 1.0 range based on card center
        _localOffset = Offset(
          (localPosition.dx - (size.width / 2)) / (size.width / 2),
          (localPosition.dy - (size.height / 2)) / (size.height / 2),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hardware accelerated 3D tilt
    final Matrix4 transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001) // perspective
      ..rotateX(-_localOffset.dy * 0.1) // tilt vertical
      ..rotateY(_localOffset.dx * 0.1); // tilt horizontal

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) {
          if (widget.onTap != null || widget.onLongPress != null) {
            _updateTilt(details.localPosition);
            setState(() => _isPressed = true);
          }
        },
        onPanUpdate: (details) {
          if (_isPressed) _updateTilt(details.localPosition);
        },
        onPanEnd: (_) {
          setState(() {
            _isPressed = false;
            _localOffset = Offset.zero;
          });
        },
        onTapUp: (_) {
          setState(() {
            _isPressed = false;
            _localOffset = Offset.zero;
          });
          widget.onTap?.call();
        },
        onPanCancel: () {
          setState(() {
            _isPressed = false;
            _localOffset = Offset.zero;
          });
        },
        onLongPress: widget.onLongPress != null ? () {
          setState(() {
            _isPressed = false;
            _localOffset = Offset.zero;
          });
          widget.onLongPress?.call();
        } : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          transform: transform,
          transformAlignment: Alignment.center,
          child: AnimatedScale(
            scale: _isPressed ? widget.scaleDown : 1.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.elasticOut,
            child: SizedBox(key: _key, child: widget.child),
          ),
        ),
      ),
    );
  }
}
