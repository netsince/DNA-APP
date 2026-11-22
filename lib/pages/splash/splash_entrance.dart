import 'package:flutter/material.dart';

import 'logo_painter.dart';

/// 缩放淡入在进度 [t]（0..1）时的缩放比。
///
/// 抽成纯函数是为了能被测试直接验算 —— 早期版本幅度只有 14%，还被二次缓动吃掉，
/// 肉眼看不出在放大，和「淡入」几乎一样。
double splashZoomScale(double t) =>
    0.45 + 0.55 * Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

/// 缩放淡入的可见度下限：**第一帧就得让人看见点东西**。
///
/// 从 0 开始的话，窗口已经出来了、画面上却什么都没有 —— 和「白屏/卡住」没区别。
/// 给一条从 0.35 起步的曲线：开头是"淡淡的但确实在那儿"，再快速显形。
const double _kZoomMinOpacity = 0.35;

/// 缩放淡入在进度 [t] 时的不透明度：前 15% 就把自己显出来，
/// 剩下的时间留给「变大」这件事被看见。
double splashZoomOpacity(double t) {
  final double appear = Curves.easeOut.transform((t / 0.15).clamp(0.0, 1.0));
  return _kZoomMinOpacity + (1 - _kZoomMinOpacity) * appear;
}

/// 淡入在进度 [t] 时的不透明度（只做透明度，没有任何缩放）。
double splashFadeOpacity(double t) =>
    Curves.easeInOut.transform(t.clamp(0.0, 1.0));

/// 「缩放淡入」那一帧的 logo（白墨 Painter，不依赖任何纹理/着色器）。
///
/// 液态玻璃开场要先放它，等玻璃就绪再切过去 —— 所以它得能独立渲染。
class SplashZoomLogo extends StatelessWidget {
  const SplashZoomLogo({super.key, required this.progress, this.size = 120});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: splashZoomOpacity(progress),
      child: Transform.scale(
        scale: splashZoomScale(progress),
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: LogoPainter(drawProgress: 1, fillProgress: 1),
          ),
        ),
      ),
    );
  }
}
