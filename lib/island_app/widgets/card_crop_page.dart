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

/// 「自由剪图」开关：打开后**所有图片编辑器**的裁剪比例限制一律失效。
///
/// 由「高级 → 命令」输入 `freeimage` 打开设置页切换（默认关）。
///
/// ## 为什么是模块级开关，而不是从 controller 逐层传参
///
/// 图片编辑器分散在**主应用**与**内嵌社区**两个子应用里：角色卡发布页与 TA 编辑器
/// 在主应用（能拿到主 controller），而社区的头像编辑页是 `const ProfileEditPage()`
/// —— 它连自己的 controller 都拿不到，更看不到主应用的设置。而「要不要锁比例」这条
/// 规则只应该有一份，且必须对所有走 [openCropPage] 的编辑器生效（将来新加的也不该漏）。
/// 所以把它放在裁剪入口旁边，值只有**一个来源**：[bind] 注入的读取回调（指向
/// `AppController.settings.freeImageCrop`），这里不存副本，因此不存在"两处状态不一致"。
///
/// 直接调 `ImageCropper().cropImage` 的编辑器（目前只有 TA 编辑器）也必须读 [enabled]，
/// 由 `test/free_image_crop_test.dart` 的静态守护用例盯着。
abstract final class FreeImageCrop {
  static bool Function()? _read;

  /// 是否处于自由剪图模式（未绑定读取回调时一律 false，即保持原来的锁定行为）。
  static bool get enabled => _read?.call() ?? false;

  /// 注入读取回调（`AppController` 启动时绑定一次，指向当前设置）。
  static void bind(bool Function() read) => _read = read;

  /// 测试用：直接给定一个固定值。
  @visibleForTesting
  static void debugSet(bool Function() read) => _read = read;
}

/// 调起图片裁剪页（基于 `image_cropper` 生态包）。
///
/// 返回裁剪后的图片字节（PNG 编码），用户取消则返回 null。
/// [aspect] 为槽位要求的裁剪比例，默认会**锁定**，用户在裁剪界面里不能改成别的比例；
/// 打开「自由剪图」（见 [FreeImageCrop]）后不再锁定，想剪成什么比例就剪什么比例。
Future<Uint8List?> openCropPage(
  BuildContext context, {
  required Uint8List sourceBytes,
  required CropAspect aspect,
}) {
  return platform.openCropPage(
    context,
    sourceBytes: sourceBytes,
    aspect: aspect,
  );
}
