import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_cropper/image_cropper.dart';

import 'card_crop_page.dart';

/// Web 端裁剪实现：Web 实现直接以 `data:` URL 作为图片源，无需临时文件。
/// 返回裁剪后的字节（PNG 编码）；取消返回 null。
Future<Uint8List?> openCropPage(
  BuildContext context, {
  required Uint8List sourceBytes,
  required CropAspect aspect,
}) async {
  final dataUrl = 'data:image/png;base64,${base64Encode(sourceBytes)}';
  try {
    final cropped = await ImageCropper().cropImage(
      sourcePath: dataUrl,
      // 之前这里完全没传比例，Web 端等于自由裁剪；补上与原生端一致的锁定比例。
      aspectRatio: CropAspectRatio(ratioX: aspect.ratio, ratioY: 1),
      compressFormat: ImageCompressFormat.png,
      compressQuality: 92,
      uiSettings: <PlatformUiSettings>[
        WebUiSettings(context: context),
      ],
    );
    if (cropped == null) return null;
    return await cropped.readAsBytes();
  } catch (_) {
    return null;
  }
}
