import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? boxShadow;
  final Color? color;
  final Color? accent;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.opacity = 0.08,
    this.borderRadius,
    this.border,
    this.padding,
    this.boxShadow,
    this.color,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? (isDark 
              ? Colors.white.withValues(alpha: opacity) 
              : Colors.black.withValues(alpha: opacity * 0.5)),
            borderRadius: borderRadius ?? BorderRadius.circular(24),
            border: border ?? Border.all(
              color: (accent ?? (isDark ? Colors.white : Colors.black)).withValues(alpha: accent != null ? 0.2 : 0.1),
              width: accent != null ? 1.5 : 1.2,
            ),
            boxShadow: [
              if (accent != null)
                BoxShadow(
                  color: accent!.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
              if (boxShadow != null) ...boxShadow!,
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassCardInteractive extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? accent;

  const GlassCardInteractive({
    super.key,
    required this.child,
    this.onTap,
    this.blur = 15.0,
    this.opacity = 0.08,
    this.borderRadius,
    this.padding,
    this.accent,
  });

  @override
  State<GlassCardInteractive> createState() => _GlassCardInteractiveState();
}

class _GlassCardInteractiveState extends State<GlassCardInteractive> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: GlassCard(
            blur: widget.blur,
            opacity: _isHovered ? widget.opacity * 1.5 : widget.opacity,
            borderRadius: widget.borderRadius,
            padding: widget.padding,
            accent: widget.accent,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
