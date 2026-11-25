import 'package:flutter/painting.dart';

/// 解码尺寸上限：**只限一条边**，另一边留给引擎按比例算。
///
/// 为什么必须只给一条：`ResizeImage(width: w, height: h)` 两边都给时，解码器会
/// 把图片**拉伸**成 w×h（引擎按 targetWidth/targetHeight 直接出图，不保持宽高比）。
/// 曾经这里同时传了「整屏最长边」两次，结果聊天背景里的人脸被横向拉宽 ——
/// 图看起来像被「裁剪坏了」，其实是解码阶段就被压扁了。
///
/// 取哪一条：和屏幕同向的那条。竖屏限制高度、横屏限制宽度，这样「按显示尺寸
/// 解码」才真的省内存；限制另一条时竖图会几乎不缩（宽度本来就不大）。
///
/// 窗口尚未布局（尺寸为 0 / NaN）时返回两条都空，交给默认解码。
({int? width, int? height}) decodeLimitFor(
  Size logical, {
  int minEdge = 800,
  int maxEdge = 2560,
}) {
  final double w = logical.width;
  final double h = logical.height;
  // 两条边都要检查：只判最长边会漏掉「一条 NaN、另一条正常」的窗口
  //（NaN > x 恒为 false，最长边会落到正常那条上，于是限制了一个没布局的视口）。
  if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0 || maxEdge <= 0) {
    return (width: null, height: null);
  }
  final double longest = w > h ? w : h;
  final int edge = longest.round().clamp(minEdge, maxEdge);
  // 正方形视口（极少见）随机取一条即可，反正另一条也不会更小。
  return w > h ? (width: edge, height: null) : (width: null, height: edge);
}

/// 按 [decodeLimitFor] 的结论包一层 [ResizeImage]。
///
/// [allowUpscaling] 恒为 false：小图原样解码，别为了填满屏幕把图放大。
ImageProvider limitDecode(ImageProvider provider, Size logical) {
  final ({int? width, int? height}) limit = decodeLimitFor(logical);
  if (limit.width == null && limit.height == null) return provider;
  return ResizeImage(
    provider,
    width: limit.width,
    height: limit.height,
    allowUpscaling: false,
  );
}
