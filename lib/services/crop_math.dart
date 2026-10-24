import 'dart:ui';

/// 裁剪页的纯计算部分（不依赖 widget，方便单测）。
///
/// 服务端会按槽位强制校验宽高比（见 card_publish_service.validate_image_slots），
/// 所以「输出比例必须等于目标比例」是一条硬约束 —— 放在这里用测试守住。

/// 按视口与目标比例算出居中的裁剪框（四周留 [padding]）。
///
/// [aspect] 为 null 表示自由裁剪：返回铺满可用区域的矩形。
Rect computeCropRect(Size viewport, double? aspect, {double padding = 16}) {
  final double availW = viewport.width - padding * 2;
  final double availH = viewport.height - padding * 2;
  if (availW <= 0 || availH <= 0) {
    return Rect.zero;
  }
  if (aspect == null) {
    return Rect.fromLTWH(padding, padding, availW, availH);
  }
  double w = availW;
  double h = w / aspect;
  if (h > availH) {
    h = availH;
    w = h * aspect;
  }
  return Rect.fromCenter(
    center: Offset(viewport.width / 2, viewport.height / 2),
    width: w,
    height: h,
  );
}

/// 源矩形 → 输出像素尺寸：长边不超过 [maxLongSide]，并保持比例。
///
/// 返回的宽高都是整数像素；对极端窄条做了下限 1 的保护。
({int width, int height}) outputSizeFor(
  Rect source, {
  int maxLongSide = 1600,
}) {
  final double longSide = source.width > source.height ? source.width : source.height;
  final double scale = longSide > maxLongSide ? maxLongSide / longSide : 1.0;
  final int w = (source.width * scale).round().clamp(1, 100000);
  final int h = (source.height * scale).round().clamp(1, 100000);
  return (width: w, height: h);
}
