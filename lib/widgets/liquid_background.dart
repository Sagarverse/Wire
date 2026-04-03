import 'dart:math' as math;
import 'package:flutter/material.dart';

class LiquidBackground extends StatefulWidget {
  final Widget child;
  const LiquidBackground({super.key, required this.child});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: Theme.of(context).colorScheme.surface),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [
                        Color(0xFF050914),
                        Color(0xFF0A1221),
                        Color(0xFF111C2E),
                      ]
                    : const [
                        Color(0xFFF5F7FC),
                        Color(0xFFEEF3FF),
                        Color(0xFFEFF7F7),
                      ],
              ),
            ),
          ),
        ),
        // ** FIX: RepaintBoundary isolates liquid animation repaints
        // from child widget tree — prevents unnecessary child rebuilds **
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: LiquidPainter(_controller.value, isDark: isDark),
                size: Size.infinite,
              );
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: GridOverlayPainter(isDark: isDark),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class LiquidPainter extends CustomPainter {
  final double animationValue;
  final bool isDark;
  LiquidPainter(this.animationValue, {required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);

    void drawBlob(Offset offset, double radius, Color color) {
      paint.color = color;
      canvas.drawCircle(offset, radius, paint);
    }

    final t = animationValue * 2 * math.pi;

    drawBlob(
      Offset(
        size.width * 0.12 + 48 * math.sin(t * 0.92),
        size.height * 0.16 + 40 * math.cos(t * 0.82),
      ),
      size.width * 0.42,
      (isDark ? const Color(0xFF5F7DFF) : const Color(0xFF9FB4FF)).withValues(
        alpha: isDark ? 0.26 : 0.2,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.82 + 46 * math.cos(t * 0.74),
        size.height * 0.66 + 64 * math.sin(t * 0.52),
      ),
      size.width * 0.5,
      (isDark ? const Color(0xFF3AD3C0) : const Color(0xFF9CE9D9)).withValues(
        alpha: isDark ? 0.2 : 0.16,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.48 + 34 * math.sin(t * 1.2),
        size.height * 0.1 - 24 * math.cos(t),
      ),
      size.width * 0.3,
      (isDark ? const Color(0xFF8364FF) : const Color(0xFFC5B6FF)).withValues(
        alpha: isDark ? 0.2 : 0.14,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.32 + 36 * math.sin(t * 0.6),
        size.height * 0.82 + 24 * math.cos(t * 0.9),
      ),
      size.width * 0.24,
      (isDark ? const Color(0xFF2F98FF) : const Color(0xFFAAD0FF)).withValues(
        alpha: isDark ? 0.18 : 0.13,
      ),
    );

    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.05 : 0.12),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sheen);
  }

  @override
  bool shouldRepaint(covariant LiquidPainter oldDelegate) => true;
}

class GridOverlayPainter extends CustomPainter {
  final bool isDark;
  GridOverlayPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.04 : 0.03,
      )
      ..strokeWidth = 1;

    const spacing = 56.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridOverlayPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
