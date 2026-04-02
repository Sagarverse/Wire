import 'package:flutter/material.dart';

class StaggeredAnimatedItem extends StatefulWidget {
  final Widget child;
  final int index;
  final int delay;
  final Duration duration;
  final Curve curve;
  final double slideOffset;

  const StaggeredAnimatedItem({
    super.key,
    required this.child,
    required this.index,
    this.delay = 50,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOutCubic,
    this.slideOffset = 20.0,
  });

  @override
  State<StaggeredAnimatedItem> createState() => _StaggeredAnimatedItemState();
}

class _StaggeredAnimatedItemState extends State<StaggeredAnimatedItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, widget.slideOffset),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
      ),
    );

    // Start animation with delay based on index
    Future.delayed(Duration(milliseconds: widget.index * widget.delay), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: _slideAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Wrapper for ListView children to add staggered animation
class StaggeredList extends StatelessWidget {
  final List<Widget> children;
  final int delay;
  final Duration duration;
  final Curve curve;
  final double slideOffset;

  const StaggeredList({
    super.key,
    required this.children,
    this.delay = 50,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOutCubic,
    this.slideOffset = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        children.length,
        (index) => StaggeredAnimatedItem(
          index: index,
          delay: delay,
          duration: duration,
          curve: curve,
          slideOffset: slideOffset,
          child: children[index],
        ),
      ),
    );
  }
}
