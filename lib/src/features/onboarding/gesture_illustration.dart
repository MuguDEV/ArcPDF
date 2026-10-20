import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Looping, asset-free illustration of the reader gestures: fling, tap,
/// pinch and long-press. Purely decorative (excluded from semantics).
///
/// When [animate] is false (reduced motion, low power) or [active] is false
/// (the card is off screen) no ticker runs; a still frame is drawn instead.
class GestureIllustration extends StatefulWidget {
  const GestureIllustration({
    super.key,
    required this.animate,
    this.active = true,
  });

  final bool animate;
  final bool active;

  @override
  State<GestureIllustration> createState() => _GestureIllustrationState();
}

class _GestureIllustrationState extends State<GestureIllustration>
    with SingleTickerProviderStateMixin {
  static const _loop = Duration(milliseconds: 9600);
  // A representative still: mid-fling, pages visibly offset.
  static const _stillFrame = 0.12;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _loop);

  bool get _running => widget.animate && widget.active;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GestureIllustration oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_running) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: AspectRatio(
          aspectRatio: 1.7,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _GesturePainter(
                      t: _running ? _controller.value : _stillFrame,
                      fade: _running,
                      ink: scheme.onSurface,
                      paper: scheme.surface,
                      line: scheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GesturePainter extends CustomPainter {
  _GesturePainter({
    required this.t,
    required this.fade,
    required this.ink,
    required this.paper,
    required this.line,
  });

  final double t;
  final bool fade;
  final Color ink;
  final Color paper;
  final Color line;

  Paint _fill(Color color, double alpha) =>
      Paint()..color = color.withValues(alpha: (color.a * alpha).clamp(0, 1));

  Paint _stroke(Color color, double alpha, double width) => _fill(color, alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final scaled = t.clamp(0.0, 0.9999) * 4;
    final phase = scaled.floor();
    final p = scaled - phase;
    // Soft fade in/out at each scene boundary hides the scene swap.
    final alpha = fade ? math.min(1.0, math.min(p, 1 - p) / 0.1) : 1.0;
    final center = size.center(Offset.zero);
    final pageSize = Size(size.height * 0.5, size.height * 0.74);

    switch (phase) {
      case 0:
        _fling(canvas, center, pageSize, p, alpha);
      case 1:
        _tap(canvas, center, pageSize, p, alpha);
      case 2:
        _pinch(canvas, center, pageSize, p, alpha);
      default:
        _longPress(canvas, center, pageSize, p, alpha);
    }
  }

  void _page(Canvas canvas, Offset center, Size size, double alpha,
      {double scale = 1}) {
    final rect = Rect.fromCenter(
        center: center, width: size.width * scale, height: size.height * scale);
    final r = RRect.fromRectAndRadius(rect, Radius.circular(8 * scale));
    canvas.drawRRect(r, _fill(paper, alpha));
    canvas.drawRRect(r, _stroke(line, alpha, 1.5));
    for (var i = 0; i < 5; i++) {
      final y = rect.top + rect.height * (0.2 + i * 0.14);
      final end = i == 4 ? 0.55 : 0.82;
      canvas.drawLine(
        Offset(rect.left + rect.width * 0.18, y),
        Offset(rect.left + rect.width * end, y),
        _stroke(line, alpha * 0.7, 2 * scale),
      );
    }
  }

  void _finger(Canvas canvas, Offset at, double alpha, {double radius = 11}) {
    canvas.drawCircle(at, radius, _fill(ink, alpha * 0.85));
    canvas.drawCircle(at, radius + 4, _stroke(ink, alpha * 0.3, 2));
  }

  void _fling(Canvas canvas, Offset c, Size page, double p, double alpha) {
    final spacing = page.width * 1.25;
    // Fast start, long deceleration: a fling, not a drag.
    final travel = Curves.easeOutExpo.transform(p);
    for (var i = -1; i <= 3; i++) {
      final dx = (i - travel * 2) * spacing;
      final edge = (1 - (dx.abs() / (c.dx + page.width)).clamp(0.0, 1.0));
      _page(canvas, c.translate(dx, 0), page, alpha * edge.clamp(0.0, 1.0));
    }
    final swipe = Curves.easeOut.transform((p / 0.3).clamp(0.0, 1.0));
    final fingerAlpha = alpha * (1 - ((p - 0.3) / 0.15).clamp(0.0, 1.0));
    if (fingerAlpha > 0) {
      final from = c.translate(page.width * 0.9, page.height * 0.28);
      final to = c.translate(-page.width * 0.9, page.height * 0.28);
      final at = Offset.lerp(from, to, swipe)!;
      // Motion streak behind the fast finger.
      canvas.drawLine(Offset.lerp(from, to, math.max(0, swipe - 0.35))!, at,
          _stroke(ink, fingerAlpha * 0.35, 6));
      _finger(canvas, at, fingerAlpha);
    }
  }

  void _toolbar(Canvas canvas, Rect bounds, double amount, double alpha) {
    if (amount <= 0) return;
    final bar = Rect.fromLTWH(
        bounds.left, bounds.top - (1 - amount) * 14, bounds.width, 22);
    final r = RRect.fromRectAndCorners(bar,
        topLeft: const Radius.circular(8), topRight: const Radius.circular(8));
    canvas.drawRRect(r, _fill(ink, alpha * amount * 0.88));
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(bar.left + 14 + i * 14, bar.center.dy), 2.5,
          _fill(paper, alpha * amount));
    }
  }

  void _ripple(Canvas canvas, Offset at, double progress, double alpha) {
    if (progress <= 0 || progress >= 1) return;
    final eased = Curves.easeOut.transform(progress);
    canvas.drawCircle(
        at, 8 + 22 * eased, _stroke(ink, alpha * (1 - eased) * 0.7, 2.5));
    canvas.drawCircle(at, 7, _fill(ink, alpha * (1 - progress) * 0.9));
  }

  void _tap(Canvas canvas, Offset c, Size page, double p, double alpha) {
    _page(canvas, c, page, alpha);
    final rect =
        Rect.fromCenter(center: c, width: page.width, height: page.height);
    // Show on the first tap, hide on the second.
    final show =
        Curves.easeOutCubic.transform(((p - 0.15) / 0.12).clamp(0.0, 1.0));
    final hide =
        Curves.easeInCubic.transform(((p - 0.65) / 0.12).clamp(0.0, 1.0));
    _toolbar(canvas, rect, show * (1 - hide), alpha);
    _ripple(
        canvas, c.translate(0, page.height * 0.12), (p - 0.12) / 0.25, alpha);
    _ripple(
        canvas, c.translate(0, page.height * 0.12), (p - 0.62) / 0.25, alpha);
  }

  void _pinch(Canvas canvas, Offset c, Size page, double p, double alpha) {
    final out =
        Curves.easeInOutCubic.transform(((p - 0.15) / 0.5).clamp(0.0, 1.0));
    final back =
        Curves.easeInOutCubic.transform(((p - 0.7) / 0.25).clamp(0.0, 1.0));
    final amount = out * (1 - back);
    _page(canvas, c, page, alpha, scale: 1 + 0.35 * amount);
    final gap = 14 + amount * 38;
    final tilt = const Offset(0.8, -0.6) * gap;
    _finger(canvas, c + tilt, alpha, radius: 9);
    _finger(canvas, c - tilt, alpha, radius: 9);
    canvas.drawLine(c + tilt, c - tilt, _stroke(ink, alpha * 0.25, 2));
  }

  void _longPress(Canvas canvas, Offset c, Size page, double p, double alpha) {
    final card = Rect.fromCenter(
        center: c.translate(-page.width * 0.35, 0),
        width: page.width * 1.25,
        height: page.height * 0.5);
    final cardR = RRect.fromRectAndRadius(card, const Radius.circular(10));
    canvas.drawRRect(cardR, _fill(paper, alpha));
    canvas.drawRRect(cardR, _stroke(line, alpha, 1.5));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(card.left + 10, card.top + 10, 26, card.height - 20),
            const Radius.circular(5)),
        _fill(line, alpha * 0.5));
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(card.left + 46, card.top + 16 + i * 12),
        Offset(card.right - (i == 2 ? 40 : 14), card.top + 16 + i * 12),
        _stroke(line, alpha * 0.7, 2),
      );
    }
    final at = card.center.translate(card.width * 0.18, 4);
    final hold = ((p - 0.1) / 0.45).clamp(0.0, 1.0);
    _finger(canvas, at, alpha, radius: 9);
    // Progress ring: the press is "charging" until the menu appears.
    canvas.drawArc(Rect.fromCircle(center: at, radius: 20), -math.pi / 2,
        2 * math.pi * hold, false, _stroke(ink, alpha * 0.8, 3));
    final menu =
        Curves.easeOutBack.transform(((p - 0.58) / 0.2).clamp(0.0, 1.0));
    if (menu > 0) {
      final menuRect = Rect.fromLTWH(
          at.dx + 6, at.dy + 12, page.width * 0.95, page.height * 0.6);
      canvas.save();
      canvas.translate(menuRect.left, menuRect.top);
      canvas.scale(menu.clamp(0.0, 1.1));
      canvas.translate(-menuRect.left, -menuRect.top);
      final r = RRect.fromRectAndRadius(menuRect, const Radius.circular(10));
      canvas.drawRRect(r, _fill(ink, alpha * 0.92));
      for (var i = 0; i < 3; i++) {
        final y = menuRect.top + menuRect.height * (0.22 + i * 0.28);
        canvas.drawCircle(
            Offset(menuRect.left + 12, y), 3, _fill(paper, alpha));
        canvas.drawLine(Offset(menuRect.left + 22, y),
            Offset(menuRect.right - 10, y), _stroke(paper, alpha * 0.9, 2.5));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GesturePainter old) =>
      old.t != t ||
      old.fade != fade ||
      old.ink != ink ||
      old.paper != paper ||
      old.line != line;
}
