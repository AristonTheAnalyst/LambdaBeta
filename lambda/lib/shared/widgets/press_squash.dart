import 'package:flutter/material.dart';

class PressSquash extends StatefulWidget {
  const PressSquash({
    super.key,
    required this.child,
    required this.onTap,
    this.disabled = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool disabled;

  @override
  State<PressSquash> createState() => _PressSquashState();
}

class _PressSquashState extends State<PressSquash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.disabled) _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _controller.reverse();
    if (!widget.disabled) widget.onTap();
  }

  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Opacity(
          opacity: _opacity.value,
          child: Transform.scale(scale: _scale.value, child: child),
        ),
        child: widget.child,
      ),
    );
  }
}
