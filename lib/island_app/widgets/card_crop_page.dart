import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'card_crop_platform.dart' as platform;

/// 裁剪比例（槽位语义）。
enum CropAspect {
  square('1:1', 1),
  landscape('16:9', 16 / 9),
  portrait('9:16', 9 / 16);

  const CropAspect(this.label, this.ratio);
  final String label;

  /// 宽/高。与 app/services/card_publish_service.py 的 SLOT_ASPECT_RATIOS 保持一致。
  final double ratio;
}

/// 调起图片裁剪页（基于 `image_cropper` 生态包）。
///
/// 返回裁剪后的图片字节（PNG 编码），用户取消则返回 null。
/// [aspect] 为槽位要求的裁剪比例，会**锁定**，用户在裁剪界面里不能改成别的比例。
Future<Uint8List?> openCropPage(
  BuildContext context, {
  required Uint8List sourceBytes,
  required CropAspect aspect,
}) {
  return platform.openCropPage(context, sourceBytes: sourceBytes, aspect: aspect);
}
