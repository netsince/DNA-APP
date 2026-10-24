import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

/// 选图 + 裁剪的结果。
class PickedImage {
  const PickedImage({required this.bytes, required this.extension});

  final Uint8List bytes;

  /// 带点的扩展名（如 `.jpg`），可能为空。
  final String extension;
}

/// 「选一张图并裁剪」的能力。
///
/// 表单不自己 new ImagePicker / ImageCropper —— 这是**宿主的能力**：
/// 本体走系统图库 + 原生裁剪器，桌面端可以换成自己的裁剪页，
/// 测试可以塞一个假实现，Web 可以只用原图。表单只负责把拿到的字节存好。
abstract interface class ImagePickCapability {
  /// [aspect] 为锁定的宽高比；null 表示自由裁剪。取消返回 null。
  Future<PickedImage?> pickAndCrop({required double? aspect});
}

/// 默认实现：系统图库 + image_cropper 原生裁剪（与原来的行为一致）。
class DefaultImagePickCapability implements ImagePickCapability {
  const DefaultImagePickCapability();

  @override
  Future<PickedImage?> pickAndCrop({required double? aspect}) async {
    final ImagePicker picker = ImagePicker();
    // 不传 imageQuality：GIF 若经 image_picker 重编码会丢失逐帧动画。
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return null;
    }
    final bool isGif = picked.name.toLowerCase().endsWith('.gif');

    // 裁剪仅 Android / iOS 可用（image_cropper 无 Web/Windows 实现）；
    // GIF 跳过裁剪：image_cropper 会重编码，导致动态 GIF 退化为静态帧。
    CroppedFile? cropped;
    if (!isGif && !kIsWeb && !Platform.isWindows) {
      try {
        cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio:
              aspect == null ? null : CropAspectRatio(ratioX: aspect, ratioY: 1),
          compressQuality: 95,
          uiSettings: <PlatformUiSettings>[
            AndroidUiSettings(
              toolbarTitle: '裁剪图片',
              lockAspectRatio: aspect != null,
            ),
            IOSUiSettings(
              title: '裁剪图片',
              aspectRatioLockEnabled: aspect != null,
              resetAspectRatioEnabled: aspect == null,
            ),
          ],
        );
      } on MissingPluginException {
        cropped = null;
      } on PlatformException {
        cropped = null;
      } catch (_) {
        cropped = null;
      }
    }

    final XFile source = cropped == null ? picked : XFile(cropped.path);
    final Uint8List bytes = await source.readAsBytes();
    return PickedImage(bytes: bytes, extension: path.extension(source.name));
  }
}
