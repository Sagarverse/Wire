import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// Award-winning animated mesh gradient background.
/// Uses multiple animated gradient orbs that drift smoothly, creating
/// a living, breathing backdrop that elevates the entire app.
class LiquidBackground extends StatefulWidget {
  final Widget child;
  final Color? accent;
  const LiquidBackground({super.key, required this.child, this.accent});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
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

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
       defaultTargetPlatform == TargetPlatform.windows ||
       defaultTargetPlatform == TargetPlatform.linux);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Base color
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF060B14) : const Color(0xFFF7F9FB),
            ),
          ),
        ),

        // Animated mesh gradient orbs (both mobile & desktop)
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _MeshGradientPainter(
                    t: _controller.value,
                    isDark: isDark,
                    isDesktop: _isDesktop,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),

        // Subtle noise overlay for texture
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.5,
                  colors: [
                    Colors.transparent,
                    (isDark ? Colors.black : Colors.white).withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Grid overlay (desktop only)
        if (_isDesktop)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _GridOverlayPainter(isDark: isDark)),
              ),
            ),
          ),

        widget.child,
      ],
    );
  }
}

// ─── Mesh Gradient Painter ─────────────────────────────────────────────────────

class _MeshGradientPainter extends CustomPainter {
  final double t;
  final bool isDark;
  final bool isDesktop;

  _MeshGradientPainter({
    required this.t,
    required this.isDark,
    required this.isDesktop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t * 2 * math.pi;

    // Orb definitions: each has a base position, movement radius, speed, size, and color
    final orbs = <_GradientOrb>[
      // Primary teal orb — top left, slow drift
      _GradientOrb(
        baseX: 0.15, baseY: 0.12,
        moveX: 0.08, moveY: 0.1,
        speedX: 0.4, speedY: 0.3,
        radius: isDesktop ? 0.5 : 0.7,
        color: isDark
            ? const Color(0xFF0891B2).withValues(alpha: 0.12)
            : const Color(0xFF0891B2).withValues(alpha: 0.07),
      ),
      // Violet accent orb — right side
      _GradientOrb(
        baseX: 0.85, baseY: 0.35,
        moveX: 0.1, moveY: 0.12,
        speedX: 0.25, speedY: 0.5,
        radius: isDesktop ? 0.4 : 0.55,
        color: isDark
            ? const Color(0xFF7C3AED).withValues(alpha: 0.08)
            : const Color(0xFF7C3AED).withValues(alpha: 0.04),
      ),
      // Amber warm orb — bottom center
      _GradientOrb(
        baseX: 0.4, baseY: 0.8,
        moveX: 0.12, moveY: 0.06,
        speedX: 0.6, speedY: 0.35,
        radius: isDesktop ? 0.35 : 0.5,
        color: isDark
            ? const Color(0xFFF59E0B).withValues(alpha: 0.05)
            : const Color(0xFFF59E0B).withValues(alpha: 0.03),
      ),
      // Deep navy fill orb — background layer
      _GradientOrb(
        baseX: 0.5, baseY: 0.5,
        moveX: 0.15, moveY: 0.15,
        speedX: 0.15, speedY: 0.2,
        radius: isDesktop ? 0.8 : 1.0,
        color: isDark
            ? const Color(0xFF1A2332).withValues(alpha: 0.1)
            : const Color(0xFFE2E8F0).withValues(alpha: 0.12),
      ),
    ];

    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * (isDesktop ? 0.12 : 0.2));

    for (final orb in orbs) {
      final x = size.width * (orb.baseX + orb.moveX * math.sin(phase * orb.speedX));
      final y = size.height * (orb.baseY + orb.moveY * math.cos(phase * orb.speedY));
      final r = size.width * orb.radius;

      paint.color = orb.color;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshGradientPainter old) =>
      old.t != t || old.isDark != isDark;
}

class _GradientOrb {
  final double baseX, baseY;
  final double moveX, moveY;
  final double speedX, speedY;
  final double radius;
  final Color color;

  const _GradientOrb({
    required this.baseX, required this.baseY,
    required this.moveX, required this.moveY,
    required this.speedX, required this.speedY,
    required this.radius, required this.color,
  });
}

// ─── Grid Overlay ──────────────────────────────────────────────────────────────

class _GridOverlayPainter extends CustomPainter {
  final bool isDark;
  _GridOverlayPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.025 : 0.02,
      )
      ..strokeWidth = 0.5;

    const spacing = 64.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridOverlayPainter old) => old.isDark != isDark;
}
