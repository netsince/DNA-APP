import 'dart:math' as math;
// PathMetric 不在 material 的再导出里（Path 在、它不在），要单独拿。
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../utils/svg_path.dart';
import 'brand_paths.dart';

/// 厂商标（真实品牌图形）。
///
/// 图标数据在 [kBrandSvgPaths]：单色 24x24 路径，用 [parseSvgPath] 直接画。
/// 不引 flutter_svg —— 只需要渲染这几个固定路径，不值得为它加一整套 SVG 栈。
///
/// **未登记的厂商退回通用机器人图标**（而不是空白）：新增服务商忘了补标时，
/// 用户看到的仍是一个图标，不会出现「这一项没有图标」的破绽。
class BrandIcon extends StatelessWidget {
  const BrandIcon({
    super.key,
    required this.id,
    this.size = 18,
    this.color,
    this.progress = 1,
  });

  /// 厂商 id（与 LlmProvider.id 对应）。
  final String id;

  /// 边长。品牌标是正方形的 24x24 viewBox。
  final double size;

  /// 颜色；为空时跟随 [IconTheme]，这样放进 Chip / ListTile 会自动取到
  /// 与相邻文字一致的选中/未选中前景色。
  final Color? color;

  /// 绘制进度：1 = 完整图形，小于 1 时先按比例勾轮廓、再渐显填充。
  ///
  /// 用于「画出来」的入场动画（见 OOBE 的 StepHero）。默认 1，所以 Chip 里的
  /// 静态用法完全不受影响。
  final double progress;

  @override
  Widget build(BuildContext context) {
    final String? path = brandSvgPathFor(id);
    if (path == null) {
      return Icon(Icons.smart_toy_outlined, size: size, color: color);
    }
    final Color effective = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandPainter(
          path: path,
          color: effective,
          progress: progress,
        ),
        isComplex: true,
        // progress < 1 时每帧都在变，交给 Flutter 决定要不要缓存。
        willChange: progress < 1,
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter({
    required this.path,
    required this.color,
    required this.progress,
  });

  final String path;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Path shape = parseSvgPath(
      path,
      scale: size.width / kBrandSvgViewBox,
      // 四个厂商标的原始 SVG 都声明 fill-rule="evenodd"：OpenAI 的结、
      // DeepSeek 的鲸鱼都有镂空，用默认的 nonZero 会把洞填实。
      fillType: PathFillType.evenOdd,
    );

    if (progress >= 1) {
      canvas.drawPath(shape, _fill(color));
      return;
    }

    // 前 65% 勾轮廓，剩下的时间把填充推上来（与 LogoPainter 同一套手法）。
    const double drawEnd = 0.65;
    final double drawT = (progress / drawEnd).clamp(0.0, 1.0).toDouble();
    final double fillT =
        ((progress - drawEnd) / (1 - drawEnd)).clamp(0.0, 1.0).toDouble();

    if (drawT > 0) {
      final Path outline = Path();
      for (final PathMetric metric in shape.computeMetrics()) {
        outline.addPath(metric.extractPath(0, metric.length * drawT), Offset.zero);
      }
      canvas.drawPath(
        outline,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          // 描边宽度跟图形尺寸走：小图标下太细会看不见。
          ..strokeWidth = math.max(0.7, size.width / kBrandSvgViewBox * 0.85)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
    if (fillT > 0) {
      canvas.drawPath(shape, _fill(color.withValues(alpha: fillT)));
    }
  }

  Paint _fill(Color c) => Paint()
    ..color = c
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.progress != progress;
}
