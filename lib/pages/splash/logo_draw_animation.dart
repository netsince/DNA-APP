import 'package:flutter/material.dart';

import 'logo_painter.dart';

/// 默认动画：描边 → 填充 → 缩小再放大淡出（原来那一套，行为完全不变）。
class LogoDrawAnimation extends StatefulWidget {
  const LogoDrawAnimation({
    super.key,
    required this.durationMs,
    required this.onComplete,
  });

  final int durationMs;
  final VoidCallback onComplete;

  @override
  State<LogoDrawAnimation> createState() => _LogoDrawAnimationState();
}

class _LogoDrawAnimationState extends State<LogoDrawAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _drawAnimation;
  late Animation<double> _fillAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );

    _drawAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.47, curve: Curves.easeOut),
      ),
    );

    _fillAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.375, 0.53, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 0.8), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 60), weight: 70),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.69, 1.0, curve: Curves.easeOut),
      ),
    );

    _opacityAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.69, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward().whenComplete(() {
      if (mounted) widget.onComplete();
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
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: LogoPainter(
                  drawProgress: _drawAnimation.value,
                  fillProgress: _fillAnimation.value,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
