import 'package:flutter/material.dart';

import 'logo_painter.dart';
import 'splash_clock.dart';

/// 默认动画：描边 → 填充 → 缩小再放大淡出（原来那一套，观感不变）。
///
/// 时钟换成 [SplashClock]：冷启动掉帧时只会走慢，不会把开头几帧跳过去。
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
  late final SplashClock _clock = SplashClock(
    vsync: this,
    duration: Duration(milliseconds: widget.durationMs),
  );

  @override
  void initState() {
    super.initState();
    _clock.startAfterFirstFrame(onComplete: widget.onComplete);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  double _interval(double t, double begin, double end, Curve curve) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (BuildContext context, Widget? child) {
        final double t = _clock.value;
        final double draw = _interval(t, 0, 0.47, Curves.easeOut);
        final double fill = _interval(t, 0.375, 0.53, Curves.easeIn);
        final double exit = _interval(t, 0.69, 1.0, Curves.easeOut);
        // 1 → 0.8（占前 30%）→ 60（剩下 70%）：和原来的 TweenSequence 一致。
        final double scale = exit <= 0.3
            ? 1 + (0.8 - 1) * (exit / 0.3)
            : 0.8 + (60 - 0.8) * ((exit - 0.3) / 0.7);
        return Opacity(
          opacity: 1 - exit,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: LogoPainter(drawProgress: draw, fillProgress: fill),
              ),
            ),
          ),
        );
      },
    );
  }
}
