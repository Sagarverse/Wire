import 'package:flutter/material.dart';
import 'dart:math' as math;

class SpeedDialFAB extends StatefulWidget {
  final List<SpeedDialAction> actions;
  final IconData icon;
  final IconData? openIcon;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const SpeedDialFAB({
    super.key,
    required this.actions,
    this.icon = Icons.add,
    this.openIcon,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  State<SpeedDialFAB> createState() => _SpeedDialFABState();
}

class _SpeedDialFABState extends State<SpeedDialFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.875, // 315 degrees
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _close() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
        _controller.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = widget.backgroundColor ?? scheme.primary;
    final fgColor = widget.foregroundColor ?? Colors.white;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop
        if (_isOpen)
          GestureDetector(
            onTap: _close,
            child: AnimatedOpacity(
              opacity: _isOpen ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ),
        
        // Action buttons
        Positioned(
          bottom: 80,
          right: 0,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  widget.actions.length,
                  (index) {
                    final reversedIndex = widget.actions.length - 1 - index;
                    final action = widget.actions[reversedIndex];
                    final delay = reversedIndex * 0.05;
                    final animationValue = math.max(
                      0.0,
                      (_scaleAnimation.value - delay) / (1.0 - delay),
                    );
                    
                    return Transform.scale(
                      scale: animationValue,
                      alignment: Alignment.centerRight,
                      child: Opacity(
                        opacity: animationValue,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SpeedDialActionButton(
                            action: action,
                            onTap: () {
                              _close();
                              action.onTap();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        
        // Main FAB
        FloatingActionButton(
          onPressed: _toggle,
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          elevation: 4,
          highlightElevation: 8,
          tooltip: widget.tooltip,
          child: AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationAnimation.value * 2 * math.pi,
                child: Icon(
                  _isOpen
                      ? (widget.openIcon ?? Icons.close)
                      : widget.icon,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SpeedDialActionButton extends StatelessWidget {
  final SpeedDialAction action;
  final VoidCallback onTap;

  const _SpeedDialActionButton({
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (action.label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E2530).withValues(alpha: 0.95)
                  : const Color(0xFF2B3544).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              action.label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(width: 12),
        Material(
          color: action.backgroundColor ?? scheme.primaryContainer,
          elevation: 4,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(
                action.icon,
                color: action.foregroundColor ?? scheme.onPrimaryContainer,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SpeedDialAction {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const SpeedDialAction({
    required this.icon,
    this.label,
    required this.onTap,
    this.backgroundColor,
    this.foregroundColor,
  });
}
