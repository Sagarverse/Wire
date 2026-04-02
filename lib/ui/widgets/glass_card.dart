import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? accent;
  final bool elevated;
  final bool animateOnHover;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 14,
    this.opacity = 0.08,
    this.borderRadius = 18,
    this.padding,
    this.accent,
    this.elevated = false,
    this.animateOnHover = false,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppTheme.animationShort,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: AppTheme.curveEaseOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = widget.accent ?? scheme.primary;

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: Container(
          padding: widget.padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (isDark ? const Color(0xFF151E2E) : Colors.white).withValues(
                  alpha: isDark ? 0.76 : 0.92,
                ),
                (isDark ? const Color(0xFF101928) : const Color(0xFFF4F7FD))
                    .withValues(alpha: isDark ? 0.68 : 0.88),
              ],
            ),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.16 : 0.14),
              width: 1,
            ),
            boxShadow: widget.elevated
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: isDark ? 0.16 : 0.1),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                      spreadRadius: -4,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: accentColor.withValues(alpha: isDark ? 0.1 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                      spreadRadius: -1,
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );

    if (!widget.animateOnHover) {
      return card;
    }

    return MouseRegion(
      onEnter: (_) {
        _controller.forward();
      },
      onExit: (_) {
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: card,
      ),
    );
  }
}
