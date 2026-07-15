import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
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
  AnimationController? _controller;

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
       defaultTargetPlatform == TargetPlatform.windows ||
       defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 14),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        // Base color
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A0F1A) : const Color(0xFFF8FAFB),
            ),
          ),
        ),

        // Mobile: static radial gradient (lightweight, zero animation cost)
        if (!_isDesktop)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.5, -0.6),
                    radius: 1.4,
                    colors: isDark
                        ? [
                            const Color(0xFF0891B2).withValues(alpha: 0.08),
                            Colors.transparent,
                          ]
                        : [
                            const Color(0xFF0891B2).withValues(alpha: 0.06),
                            Colors.transparent,
                          ],
                  ),
                ),
              ),
            ),
          ),
        if (!_isDesktop)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.8, 0.7),
                    radius: 1.2,
                    colors: isDark
                        ? [
                            const Color(0xFF1E293B).withValues(alpha: 0.08),
                            Colors.transparent,
                          ]
                        : [
                            const Color(0xFFE2E8F0).withValues(alpha: 0.15),
                            Colors.transparent,
                          ],
                  ),
                ),
              ),
            ),
          ),

        // Desktop: animated liquid blobs
        if (_isDesktop && _controller != null)
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller!,
              builder: (context, child) {
                return CustomPaint(
                  painter: LiquidPainter(
                    _controller!.value,
                    isDark: isDark,
                    accent: accent,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),

        // Grid overlay (desktop only)
        if (_isDesktop)
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
    final paint = Paint();
    final t = animationValue * 2 * math.pi;

    void drawBlob(Offset offset, double radius, Color color) {
      paint.color = color;
      canvas.drawCircle(offset, radius, paint);
    }

    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);

    drawBlob(
      Offset(
        size.width * 0.15 + 60 * math.sin(t * 0.5),
        size.height * 0.2 + 80 * math.cos(t * 0.4),
      ),
      size.width * 0.8,
      (isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9)).withValues(
        alpha: isDark ? 0.08 : 0.2,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.82 + 100 * math.cos(t * 0.3),
        size.height * 0.66 + 120 * math.sin(t * 0.2),
      ),
      size.width * 0.7,
      (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.02 : 0.04,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.48 + 80 * math.sin(t * 0.7),
        size.height * 0.1 - 40 * math.cos(t * 0.6),
      ),
      size.width * 0.4,
      (isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE2E8F0)).withValues(
        alpha: isDark ? 0.05 : 0.15,
      ),
    );

    drawBlob(
      Offset(
        size.width * 0.3 + 90 * math.sin(t * 0.45),
        size.height * 0.85 + 50 * math.cos(t * 0.75),
      ),
      size.width * 0.35,
      (isDark ? const Color(0xFF262626) : const Color(0xFFF1F5F9)).withValues(
        alpha: isDark ? 0.06 : 0.12,
      ),
    );
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
