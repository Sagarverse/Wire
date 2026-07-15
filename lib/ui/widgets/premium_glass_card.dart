import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

class PremiumGlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? accent;
  final List<Color>? gradientColors;
  final bool isShimmering;

  const PremiumGlassCard({
    super.key,
    required this.child,
    this.blur = 32.0,
    this.opacity = 0.08,
    this.borderRadius,
    this.border,
    this.padding,
    this.color,
    this.accent,
    this.gradientColors,
    this.isShimmering = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bRadius = borderRadius ?? BorderRadius.circular(28);

    Widget content = ClipRRect(
      borderRadius: bRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? (isDark 
              ? Colors.white.withValues(alpha: opacity)
              : Colors.white.withValues(alpha: opacity * 2)),
            borderRadius: bRadius,
            border: border ?? Border.all(
              color: (accent ?? (isDark ? Colors.white : Colors.black))
                  .withValues(alpha: isDark ? 0.05 : 0.03),
              width: 0.8,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors ?? [
                (accent ?? Colors.white).withValues(alpha: 0.1),
                Colors.transparent,
                (accent ?? Colors.white).withValues(alpha: 0.04),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );

    if (isShimmering) {
      content = content
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .shimmer(
            duration: 3.seconds,
            color: (accent ?? Colors.white).withValues(alpha: 0.1),
          );
    }

    return Stack(
      children: [
        // Inner Glow / Secondary shadow for depth
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: bRadius,
              boxShadow: [
                BoxShadow(
                  color: (accent ?? Colors.black).withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                  spreadRadius: -8,
                ),
              ],
            ),
          ),
        ),
        content,
      ],
    );
  }
}

class PremiumGlassCardInteractive extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? accent;
  final bool isSelected;
  final bool isShimmering;

  const PremiumGlassCardInteractive({
    super.key,
    required this.child,
    this.onTap,
    this.blur = 32.0,
    this.opacity = 0.08,
    this.borderRadius,
    this.padding,
    this.accent,
    this.isSelected = false,
    this.isShimmering = false,
  });

  @override
  State<PremiumGlassCardInteractive> createState() => _PremiumGlassCardInteractiveState();
}

class _PremiumGlassCardInteractiveState extends State<PremiumGlassCardInteractive> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap != null ? () {
          HapticFeedback.lightImpact();
          widget.onTap!();
        } : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(28),
            boxShadow: [
              if (_isHovered || widget.isSelected)
                BoxShadow(
                  color: (widget.accent ?? (isDark ? Colors.white : Colors.black)).withValues(alpha: isDark ? 0.2 : 0.1),
                  blurRadius: 32,
                  spreadRadius: -4,
                ),
            ],
          ),
          child: AnimatedScale(
            scale: _isPressed ? 0.96 : (_isHovered ? 1.02 : 1.0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            child: PremiumGlassCard(
              blur: widget.blur,
              opacity: _isHovered || widget.isSelected ? widget.opacity * 1.8 : widget.opacity,
              borderRadius: widget.borderRadius,
              padding: widget.padding,
              accent: widget.isSelected ? widget.accent : ( _isHovered ? widget.accent : null),
              isShimmering: widget.isSelected,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
