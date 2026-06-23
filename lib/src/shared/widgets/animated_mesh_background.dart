import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class AnimatedMeshBackground extends StatefulWidget {
  const AnimatedMeshBackground({super.key});

  @override
  State<AnimatedMeshBackground> createState() => _AnimatedMeshBackgroundState();
}

class _AnimatedMeshBackgroundState extends State<AnimatedMeshBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Very subtle monochrome base colors
    final baseColor = theme.colorScheme.surface;
    final highlight1 = theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.3 : 0.5);
    final highlight2 = theme.colorScheme.secondaryContainer.withValues(alpha: isDark ? 0.3 : 0.5);

    return Container(
      color: baseColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Moving blobs
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final val = _controller.value;
              return CustomPaint(
                painter: _MeshPainter(
                  value: val,
                  color1: highlight1,
                  color2: highlight2,
                ),
              );
            },
          ),
          // Heavy glass blur to merge the blobs into a mesh gradient
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final double value;
  final Color color1;
  final Color color2;

  _MeshPainter({required this.value, required this.color1, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = color1
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

    final paint2 = Paint()
      ..color = color2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

    final w = size.width;
    final h = size.height;

    // Center coordinates for circular motion
    final cx1 = w * 0.5 + math.cos(value * 2 * math.pi) * w * 0.3;
    final cy1 = h * 0.3 + math.sin(value * 2 * math.pi) * h * 0.2;

    final cx2 = w * 0.5 + math.sin(value * 2 * math.pi) * w * 0.4;
    final cy2 = h * 0.7 + math.cos(value * 2 * math.pi) * h * 0.2;

    canvas.drawCircle(Offset(cx1, cy1), w * 0.6, paint1);
    canvas.drawCircle(Offset(cx2, cy2), w * 0.7, paint2);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}
