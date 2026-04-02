import 'dart:ui';
import 'package:flutter/material.dart';

class ToolCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const ToolCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> 
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _elevationAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHoverChange(bool hover) {
    if (widget.onTap != null) {
      setState(() => _isHovered = hover);
      if (hover && !_isPressed) {
        _controller.forward();
      } else if (!hover && !_isPressed) {
        _controller.reverse();
      }
    }
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      setState(() => _isPressed = true);
      _controller.reverse();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null) {
      setState(() => _isPressed = false);
      if (_isHovered) {
        _controller.forward();
      }
    }
  }

  void _onTapCancel() {
    if (widget.onTap != null) {
      setState(() => _isPressed = false);
      if (_isHovered) {
        _controller.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: enabled ? 1.0 : 0.48,
            child: Padding(
              padding: EdgeInsets.zero,
              child: MouseRegion(
                onEnter: (_) => _onHoverChange(true),
                onExit: (_) => _onHoverChange(false),
                cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
                child: GestureDetector(
                  onTapDown: _onTapDown,
                  onTapUp: _onTapUp,
                  onTapCancel: _onTapCancel,
                  onTap: widget.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        // Enhanced glow effect on hover
                        if (enabled && _isHovered)
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.3 * _glowAnimation.value),
                            blurRadius: 24 + (_elevationAnimation.value * 2),
                            offset: const Offset(0, 8),
                            spreadRadius: 2,
                          ),
                        // Deeper shadow on hover
                        if (enabled && _isHovered)
                          BoxShadow(
                            color: scheme.secondary.withValues(alpha: 0.2 * _glowAnimation.value),
                            blurRadius: 32 + (_elevationAnimation.value * 3),
                            offset: Offset(0, 4 + _elevationAnimation.value),
                            spreadRadius: -2,
                          ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Base glass card with premium styling
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    (isDark 
                                        ? const Color(0xFF1A2335) 
                                        : Colors.white
                                    ).withValues(alpha: isDark ? 0.85 : 0.95),
                                    (isDark 
                                        ? const Color(0xFF141D2E) 
                                        : const Color(0xFFF8FAFF)
                                    ).withValues(alpha: isDark ? 0.75 : 0.9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  width: 1.5,
                                  color: enabled && _isHovered
                                      ? scheme.primary.withValues(
                                          alpha: (isDark ? 0.4 : 0.3) * (0.5 + (_glowAnimation.value * 0.5)))
                                      : scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
                                ),
                                boxShadow: [
                                  // Inner glow effect
                                  BoxShadow(
                                    color: scheme.primary.withValues(
                                        alpha: 0.08 + (0.12 * _glowAnimation.value)),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                  // Depth shadow
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                        alpha: isDark ? 0.3 : 0.06),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Premium gradient icon container
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(15),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          scheme.primary.withValues(
                                              alpha: isDark ? 0.28 : 0.16),
                                          scheme.secondary.withValues(
                                              alpha: isDark ? 0.22 : 0.12),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: scheme.primary.withValues(
                                            alpha: (isDark ? 0.5 : 0.3) * 
                                                (0.7 + (_glowAnimation.value * 0.3))),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary.withValues(
                                              alpha: 0.15 * (1 + _glowAnimation.value)),
                                          blurRadius: 8 + (_glowAnimation.value * 4),
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      widget.icon,
                                      color: scheme.primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.title,
                                          style: TextStyle(
                                            color: scheme.onSurface,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          widget.subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: scheme.onSurface.withValues(
                                                alpha: isDark ? 0.68 : 0.62),
                                            fontSize: 12,
                                            height: 1.3,
                                            letterSpacing: -0.1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Animated chevron
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    transform: Matrix4.translationValues(
                                        _glowAnimation.value * 4, 0, 0),
                                    child: Icon(
                                      Icons.arrow_forward_rounded,
                                      color: scheme.primary.withValues(
                                          alpha: 0.5 + (_glowAnimation.value * 0.3)),
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Premium shimmer overlay on hover
                        if (enabled && _isHovered)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: AnimatedOpacity(
                                opacity: 0.08 * _glowAnimation.value,
                                duration: const Duration(milliseconds: 300),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        scheme.primary.withValues(alpha: 0.3),
                                        scheme.secondary.withValues(alpha: 0.2),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
