import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.blur = 12.0,
    this.opacity = 0.06,
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
              ? (accent != null ? accent!.withValues(alpha: 0.1) : Colors.white.withValues(alpha: opacity))
              : Colors.white.withValues(alpha: opacity * 1.5)),
            borderRadius: borderRadius ?? BorderRadius.circular(24),
            border: border ?? Border.all(
              color: (accent ?? (isDark ? Colors.white : Colors.black)).withValues(alpha: isDark ? 0.15 : 0.08),
              width: 1.0,
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
  final VoidCallback? onLongPress;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? accent;

  const GlassCardInteractive({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.blur = 12.0,
    this.opacity = 0.06,
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
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap != null
            ? () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        onLongPress: widget.onLongPress != null
            ? () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              }
            : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : (_isHovered ? 1.015 : 1.0),
          duration: _isPressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 280),
          curve: _isPressed ? Curves.easeIn : Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: widget.onTap == null ? 0.52 : 1.0,
            duration: const Duration(milliseconds: 200),
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
      ),
    );
  }
}
