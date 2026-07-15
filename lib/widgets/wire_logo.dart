import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Award-winning animated Wire logo.
/// A stylized "W" wire shape inside a glowing ring that pulses
/// with subtle rotation animation. Used in dashboard header and splash.
class WireLogo extends StatefulWidget {
  final double size;
  final Color? color;
  final bool showGlow;
  final bool animate;

  const WireLogo({
    super.key,
    this.size = 40,
    this.color,
    this.showGlow = false,
    this.animate = true,
  });

  @override
  State<WireLogo> createState() => _WireLogoState();
}

class _WireLogoState extends State<WireLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _WireLogoPainter(
              color: c,
              showGlow: widget.showGlow,
              phase: _ctrl.value,
            ),
          ),
        );
      },
    );
  }
}

class _WireLogoPainter extends CustomPainter {
  final Color color;
  final bool showGlow;
  final double phase;

  _WireLogoPainter({
    required this.color,
    required this.showGlow,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w * 0.42;
    final t = phase * 2 * math.pi;

    // Animated glow behind logo
    if (showGlow) {
      final glowAlpha = 0.08 + 0.06 * math.sin(t);
      final glowPaint = Paint()
        ..color = color.withValues(alpha: glowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.25);
      canvas.drawCircle(center, radius * 1.3, glowPaint);
    }

    // Outer ring with gradient-like rotation
    final ringAlpha = 0.2 + 0.08 * math.sin(t * 0.5);
    final ringPaint = Paint()
      ..color = color.withValues(alpha: ringAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02;
    canvas.drawCircle(center, radius, ringPaint);

    // Animated arc on the ring (spinning effect)
    final arcPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round;
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(arcRect, t, math.pi * 0.4, false, arcPaint);

    // Inner fill circle
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.06 + 0.03 * math.sin(t * 1.5))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.85, fillPaint);

    // Draw the "W" wire shape
    final wirePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final left = w * 0.26;
    final right = w * 0.74;
    final top = h * 0.32;
    final midBottom = h * 0.68;
    final midX = w * 0.5;

    path.moveTo(left, top);
    path.lineTo(left + (midX - left) * 0.5, midBottom);
    path.lineTo(midX, midBottom - h * 0.1);
    path.lineTo(right - (right - midX) * 0.5, midBottom);
    path.lineTo(right, top);

    // Wire glow
    if (showGlow) {
      final wireGlow = Paint()
        ..color = color.withValues(alpha: 0.25 + 0.1 * math.sin(t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.035);
      canvas.drawPath(path, wireGlow);
    }

    canvas.drawPath(path, wirePaint);

    // Signal dots at the tips — pulsing size
    final dotR = w * (0.03 + 0.008 * math.sin(t * 2));
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(left, top), dotR, dotPaint);
    canvas.drawCircle(Offset(right, top), dotR, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _WireLogoPainter old) =>
      old.color != color || old.showGlow != showGlow || old.phase != phase;
}
