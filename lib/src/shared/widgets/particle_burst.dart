import 'dart:math' as math;
import 'package:flutter/material.dart';

class ParticleBurst extends StatefulWidget {
  final Widget child;
  final GlobalKey<ParticleBurstState> burstKey;
  final Color burstColor;

  const ParticleBurst({
    super.key,
    required this.child,
    required this.burstKey,
    required this.burstColor,
  });

  @override
  ParticleBurstState createState() => ParticleBurstState();
}

class ParticleBurstState extends State<ParticleBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _random = math.Random();
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void triggerBurst() {
    _particles.clear();
    for (int i = 0; i < 20; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = 30 + _random.nextDouble() * 50;
      final size = 4 + _random.nextDouble() * 6;
      _particles.add(_Particle(angle: angle, speed: speed, size: size));
    }
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        widget.child,
        if (_controller.isAnimating)
          Positioned.fill(
            child: CustomPaint(
              painter: _BurstPainter(
                progress: Curves.easeOutCirc.transform(_controller.value),
                particles: _particles,
                color: widget.burstColor,
              ),
            ),
          ),
      ],
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;

  _Particle({required this.angle, required this.speed, required this.size});
}

class _BurstPainter extends CustomPainter {
  final double progress;
  final List<_Particle> particles;
  final Color color;

  _BurstPainter({required this.progress, required this.particles, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final paint = Paint()
      ..color = color.withValues(alpha: (1.0 - progress))
      ..style = PaintingStyle.fill;

    for (final p in particles) {
      final distance = p.speed * progress;
      final x = cx + math.cos(p.angle) * distance;
      final y = cy + math.sin(p.angle) * distance;
      canvas.drawCircle(Offset(x, y), p.size * (1 - progress * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
