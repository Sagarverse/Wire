import 'dart:math' as math;
import 'package:flutter/material.dart';

class LiquidBackground extends StatefulWidget {
  final Widget child;
  final Color? accent;
  const LiquidBackground({super.key, required this.child, this.accent});

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
              color: isDark ? Colors.black : const Color(0xFFF5F7FC),
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
                painter: LiquidPainter(
                  _controller.value, 
                  isDark: isDark, 
                  accent: widget.accent ?? Theme.of(context).colorScheme.primary,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: GridOverlayPainter(isDark: isDark)),
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
  final Color accent;
  LiquidPainter(this.animationValue, {required this.isDark, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90);

    void drawBlob(Offset offset, double radius, Color color) {
      paint.color = color;
      canvas.drawCircle(offset, radius, paint);
    }

    final t = animationValue * 2 * math.pi;

    drawBlob(
      Offset(
        size.width * 0.12 + 48 * math.sin(t * 0.94),
        size.height * 0.16 + 40 * math.cos(t * 0.79),
      ),
      size.width * 0.42,
      (isDark ? Colors.white : Colors.blue).withValues(
        alpha: isDark ? 0.03 : 0.08,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.82 + 46 * math.cos(t * 0.71),
        size.height * 0.66 + 64 * math.sin(t * 0.55),
      ),
      size.width * 0.5,
      (isDark ? Colors.white : Colors.teal).withValues(
        alpha: isDark ? 0.02 : 0.06,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.48 + 34 * math.sin(t * 1.18),
        size.height * 0.1 - 24 * math.cos(t * 0.97),
      ),
      size.width * 0.3,
      (isDark ? Colors.white : Colors.purple).withValues(
        alpha: isDark ? 0.02 : 0.05,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.32 + 36 * math.sin(t * 0.62),
        size.height * 0.82 + 24 * math.cos(t * 0.88),
      ),
      size.width * 0.24,
      (isDark ? const Color(0xFF2F98FF) : const Color(0xFFAAD0FF)).withValues(
        alpha: isDark ? 0.18 : 0.13,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.70 + 28 * math.cos(t * 0.78),
        size.height * 0.22 + 36 * math.sin(t * 1.05),
      ),
      size.width * 0.20,
      accent.withValues(
        alpha: isDark ? 0.08 : 0.07,
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
  bool shouldRepaint(covariant LiquidPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.isDark != isDark ||
      oldDelegate.accent != accent;
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
