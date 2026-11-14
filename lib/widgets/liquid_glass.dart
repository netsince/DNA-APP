import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 液态玻璃：在普通「半透明 + 描边」之外，补上三层光学细节。
///
/// 1. **厚度渐变**：左上略亮、右下略沉，玻璃才有体积；
/// 2. **镜面高光**：左上角一团很淡的径向白光，模拟光源掠过；
/// 3. **折射边**：上沿白边（亮）与下沿暗边（沉）分开画，圆角处自然收口。
///
/// 全部用 [CustomPaint] 画，不做离屏合成；静止时零开销，
/// 滚动时只是一个图层内的 draw，比 BackdropFilter 便宜得多。
/// 需要真实背景模糊时用 `blur` 参数（会离屏合成，慎用于长列表）。
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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// 背景模糊强度（0 = 不模糊）。大列表里保持 0。
  final double blur;

  /// 是否加一层柔和投影，把面板「托起来」。
  final bool elevated;

  /// 光学强度倍率，1 为默认；浅色主题可以降到 0.6。
  final double intensity;

  /// 可选染色（一般传 `colorScheme.primary`），模拟边缘色散。
  final Color? tint;

  /// 覆盖底色。列表里的大块卡片建议传更透的 [AppSurfaces.glassFillWeak]，
  /// 否则多层高光叠起来会把深色玻璃抬成灰板。
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final double k = dark ? intensity : intensity * 0.62;

    Widget content = Padding(padding: padding, child: child);
    content = CustomPaint(
      painter: _LiquidGlassPainter(
        borderRadius: borderRadius,
        fill: fill ?? (dark ? AppSurfaces.glassFill : AppSurfaces.glassFillLight),
        tint: tint,
        intensity: k,
      ),
      willChange: false,
      child: content,
    );

    if (blur > 0) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(borderRadius: borderRadius, child: content);
    }

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
    this.tint,
  });

  final BorderRadius borderRadius;
  final Color fill;
  final double intensity;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double r = borderRadius.topLeft.x.clamp(0, size.shortestSide / 2);
    final RRect rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));

    // 1. 厚度渐变
    // 先压一层微暗底：多层高光叠起来才不会把深色玻璃抬成灰板。
    final Color base = Color.alphaBlend(Colors.black.withValues(alpha: 0.05 * intensity), fill);
    final Color top = Color.alphaBlend(Colors.white.withValues(alpha: 0.035 * intensity), base);
    final Color bottom = Color.alphaBlend(Colors.black.withValues(alpha: 0.11 * intensity), base);
    canvas.drawRRect(
      rrect,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), <Color>[top, bottom]),
    );

    // 2. 边缘色散（可选）
    final Color? t = tint;
    if (t != null) {
      canvas.drawRRect(rrect, Paint()..color = t.withValues(alpha: 0.022 * intensity));
    }

    // 3. 镜面高光
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.18, -size.height * 0.18),
          size.width * 0.60,
          <Color>[Colors.white.withValues(alpha: 0.050 * intensity), Colors.transparent],
          <double>[0.0, 1.0],
        ),
    );

    // 4. 折射边：上亮下暗，各画半圈渐变
    final RRect rim = rrect.deflate(0.75);
    final double w = 1.2 + 0.2 * intensity;
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.85, size.height * 0.85),
          <Color>[Colors.white.withValues(alpha: 0.24 * intensity), Colors.white.withValues(alpha: 0.02)],
          <double>[0.0, 1.0],
        ),
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = ui.Gradient.linear(
          Offset(size.width, size.height),
          Offset(size.width * 0.15, size.height * 0.15),
          <Color>[Colors.black.withValues(alpha: 0.34 * intensity), Colors.transparent],
          <double>[0.0, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter old) =>
      old.fill != fill || old.intensity != intensity || old.tint != tint || old.borderRadius != borderRadius;
}
