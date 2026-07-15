import 'package:flutter/material.dart';

/// Wire app logo drawn entirely with code — no image assets needed.
/// A stylized "W" made of connected signal/wire lines with a glow effect.
class WireLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool showGlow;

  const WireLogo({
    super.key,
    this.size = 40,
    this.color,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WireLogoPainter(color: c, showGlow: showGlow),
      ),
    );
  }
}

class _WireLogoPainter extends CustomPainter {
  final Color color;
  final bool showGlow;

  _WireLogoPainter({required this.color, required this.showGlow});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w * 0.42;

    // Background circle
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Outer ring
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025;
    canvas.drawCircle(center, radius, ringPaint);

    // Draw the "W" wire shape
    final wirePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // W shape within the circle
    final left = w * 0.25;
    final right = w * 0.75;
    final top = h * 0.3;
    final bottom = h * 0.65;
    final midBottom = h * 0.72;
    final midX = w * 0.5;

    path.moveTo(left, top);
    path.lineTo(left + (midX - left) * 0.5, midBottom);
    path.lineTo(midX, bottom - h * 0.08);
    path.lineTo(right - (right - midX) * 0.5, midBottom);
    path.lineTo(right, top);

    if (showGlow) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.04);
      canvas.drawPath(path, glowPaint);
    }

    canvas.drawPath(path, wirePaint);

    // Signal dots at the tips
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final dotR = w * 0.035;
    canvas.drawCircle(Offset(left, top), dotR, dotPaint);
    canvas.drawCircle(Offset(right, top), dotR, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _WireLogoPainter old) =>
      old.color != color || old.showGlow != showGlow;
}
