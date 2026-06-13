import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

  bool _showBurst = false;
  Offset _burstPosition = Offset.zero;

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
      child: Listener(
        onPointerDown: (event) {
          if (widget.onTap != null || widget.onLongPress != null) {
            _updateTilt(event.localPosition);
          }
        },
        onPointerMove: (event) {
          if (_isPressed) _updateTilt(event.localPosition);
        },
        onPointerUp: (_) {
          if (_isPressed && mounted) {
            setState(() {
              _isPressed = false;
              _localOffset = Offset.zero;
            });
          }
        },
        onPointerCancel: (_) {
          if (_isPressed && mounted) {
            setState(() {
              _isPressed = false;
              _localOffset = Offset.zero;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            if (widget.onTap != null || widget.onLongPress != null) {
              setState(() => _isPressed = true);
            }
          },
          onTapUp: (details) {
            if (widget.onTap != null) {
              setState(() {
                _burstPosition = details.localPosition;
                _showBurst = true;
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) setState(() => _showBurst = false);
              });
            }
            setState(() {
              _isPressed = false;
              _localOffset = Offset.zero;
            });
            widget.onTap?.call();
          },
          onTapCancel: () {
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
              child: SizedBox(
                key: _key,
                child: Stack(
                  children: [
                    widget.child,
                    if (_showBurst)
                      Positioned(
                        left: _burstPosition.dx - 50,
                        top: _burstPosition.dy - 50,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ).animate().scale(begin: const Offset(0.0, 0.0), end: const Offset(5.0, 5.0), duration: 400.ms, curve: Curves.easeOutCirc).fadeOut(duration: 300.ms),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
