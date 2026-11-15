import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 液态玻璃（第三版）。
///
/// 光学模型取自三份公开实现（MIT / Apache-2.0 / MPL）：
///
/// * `zhouwu97/FlutterLiquidglass` —— `shaders/liquid_glass.frag`：
///   圆角 SDF 求「离边距离 d」，`band = 1 + d/height`、`circle = 1 - sqrt(1-band²)`
///   得到圆弧截面，折射位移 = `-normal * circle * amount`；边缘光用
///   `surfaceLight()` 三个高斯（outline d≈-0.7 / bloom d≈-1.4 / caustic d≈-3.0）
///   加双向 Fresnel 峰值 `pow(dot(n,±l), 7)`，同一套法线同时驱动轮廓、折射、高光。
/// * `renancaraujo/liquido` —— 后景加权模糊 + soft-light 染色 + 按角度的 shine/shadow。
/// * `sdegenaar/liquid_glass_renderer` —— 玻璃组共享一次背景捕获、按像素对齐。
///
/// 这一版是**几何近似**（不抓背景纹理、不引依赖）：
/// 用三道同心描边分别模拟 outline / bloom / caustic，颜色用扫描渐变按「光源方向」
/// 做双向峰值，等价于 shader 里的 a、b 两个 Fresnel 项；染色走 soft-light。
///
/// 想要像素级折射（含七通道色散）必须走 shader + 背景捕获，见 PR 说明。
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = AppRadius.mdAll,
    this.blur = 0,
    this.elevated = false,
    this.intensity = 1,
    this.tint,
    this.fill,
    this.lightFromTopLeft = true,
    this.lightAngleOverride,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// 背景模糊强度（0 = 不模糊）。大列表里保持 0。
  final double blur;

  /// 是否加一层柔和投影，把面板「托起来」。
  final bool elevated;

  /// 光学强度倍率，1 为默认；浅色主题会自动降到 0.62。
  final double intensity;

  /// 可选染色（相当于 shader 里的 uTint），一般传 `colorScheme.primary`。
  final Color? tint;

  /// 覆盖底色。列表里的大块卡片建议传更透的 [AppSurfaces.glassFillWeak]。
  final Color? fill;

  /// 光源方位：默认左上（-0.65, -1 方向），与 shader 的 surfaceLight 一致。
  final bool lightFromTopLeft;

  /// 覆盖光源角度（弧度，0 = 正右，顺时针增加）。
  /// 侧栏这类可悬停的元素可以传「指针相对中心的极角」，高光就会跟着鼠标走。
  final double? lightAngleOverride;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final double k = dark ? intensity : intensity * 0.62;

    Widget content = Padding(padding: padding, child: child);
    content = CustomPaint(
      painter: _LiquidGlassPainter(
        borderRadius: borderRadius,
        fill: fill ?? (dark ? AppSurfaces.glassFill : AppSurfaces.glassFillLight),
        tint: tint ?? theme.colorScheme.primary,
        intensity: k,
        lightAngle: lightAngleOverride ?? (lightFromTopLeft ? -2.15 : 0.99),
      ),
      willChange: false,
      child: content,
    );

    content = ClipRRect(
      borderRadius: borderRadius,
      child: blur > 0
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: content,
            )
          : content,
    );

    if (!elevated) return content;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: AppShadows.glass),
      child: content,
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  const _LiquidGlassPainter({
    required this.borderRadius,
    required this.fill,
    required this.intensity,
    required this.tint,
    required this.lightAngle,
  });

  final BorderRadius borderRadius;
  final Color fill;
  final double intensity;
  final Color tint;
  final double lightAngle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final double r = borderRadius.topLeft.x.clamp(0, size.shortestSide / 2);
    final RRect rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double diagonal = math.sqrt(size.width * size.width + size.height * size.height);
    final double rim = math.min(size.shortestSide * 0.5, 12);

    // ① 厚度渐变（左上亮 → 右下沉）
    final Color base = Color.alphaBlend(Colors.black.withValues(alpha: 0.05 * intensity), fill);
    final Color top = Color.alphaBlend(Colors.white.withValues(alpha: 0.035 * intensity), base);
    final Color bottom = Color.alphaBlend(Colors.black.withValues(alpha: 0.11 * intensity), base);
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          <Color>[top, bottom],
        ),
    );

    // ② soft-light 染色（对应 shader 的 uTint，直接盖会显脏）
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = tint.withValues(alpha: (0.10 * intensity).clamp(0.0, 0.3))
        ..blendMode = BlendMode.softLight,
    );

    // ③ 边缘光：outline / bloom / caustic 三圈高斯
    //    每圈都用扫描渐变给「主光方向」与「反光方向」两个峰值（a、b 两项）。
    _rimRing(
      canvas,
      rrect,
      inset: 0.7,
      width: 0.75,
      peakA: 0.62,
      peakB: 0.28,
      baseAlpha: 0.10,
      sweepSpan: 2.6,
      center: center,
      diagonal: diagonal,
      rim: rim,
    );
    _rimRing(
      canvas,
      rrect,
      inset: 1.6,
      width: 1.6,
      peakA: 0.16,
      peakB: 0.14,
      baseAlpha: 0.03,
      sweepSpan: 1.9,
      center: center,
      diagonal: diagonal,
      rim: rim,
    );
    _rimRing(
      canvas,
      rrect,
      inset: 3.2,
      width: 2.0,
      peakA: 0.02,
      peakB: 0.09,
      baseAlpha: 0.012,
      sweepSpan: 1.4,
      center: center,
      diagonal: diagonal,
      rim: rim,
    );

    // ④ 顶部大面积柔光，压住整体发平
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.30, -size.height * 0.05),
          diagonal * 0.62,
          <Color>[
            Colors.white.withValues(alpha: 0.045 * intensity),
            Colors.transparent,
          ],
          <double>[0.0, 1.0],
        ),
    );
  }

  /// 一圈边缘光。两条扫描渐变叠加：主光（lightAngle）与反光（+π），
  /// 用不同强度的峰值模拟 shader 里 `pow(dot(n, l), 7)` 与 `pow(dot(n, -l), 7)`。
  void _rimRing(
    Canvas canvas,
    RRect rrect, {
    required double inset,
    required double width,
    required double peakA,
    required double peakB,
    required double baseAlpha,
    required double sweepSpan,
    required Offset center,
    required double diagonal,
    required double rim,
  }) {
    final RRect ring = rrect.deflate(inset + width / 2);
    if (ring.width <= 0 || ring.height <= 0) return;
    final double a = (baseAlpha + peakA * 0.10) * intensity;
    final double b = (baseAlpha + peakB * 0.10) * intensity;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    // 主光
    paint.shader = ui.Gradient.sweep(
      center,
      <Color>[
        Colors.white.withValues(alpha: a * 0.25),
        Colors.white.withValues(alpha: a),
        Colors.white.withValues(alpha: a * 0.35),
        Colors.white.withValues(alpha: a * 0.12),
      ],
      <double>[0.0, 0.16, 0.46, 1.0],
      TileMode.clamp,
      lightAngle,
      lightAngle + math.pi * 2,
    );
    canvas.drawRRect(ring, paint);

    // 反光（背面 Fresnel）
    paint.shader = ui.Gradient.sweep(
      center,
      <Color>[
        Colors.white.withValues(alpha: b * 0.18),
        Colors.white.withValues(alpha: b),
        Colors.white.withValues(alpha: b * 0.2),
        Colors.white.withValues(alpha: b * 0.08),
      ],
      <double>[0.0, 0.16, 0.46, 1.0],
      TileMode.clamp,
      lightAngle + math.pi,
      lightAngle + math.pi * 3,
    );
    canvas.drawRRect(ring, paint);

    // 边缘色散（很淡的一圈，冷/暖分色；shader 里是七通道采样，这里只做边光分色）
    if (intensity > 0.9 && width <= 0.9) {
      paint
        ..strokeWidth = width * 0.6
        ..shader = ui.Gradient.sweep(
          center,
          <Color>[
            const Color(0x0000FFFF),
            const Color(0x2233DDFF),
            const Color(0x00FF88CC),
          ],
          <double>[0.0, 0.5, 1.0],
          TileMode.clamp,
          lightAngle + math.pi * 0.5,
          lightAngle + math.pi * 2.5,
        );
      canvas.drawRRect(ring, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter old) =>
      old.fill != fill ||
      old.intensity != intensity ||
      old.tint != tint ||
      old.borderRadius != borderRadius ||
      old.lightAngle != lightAngle;
}
