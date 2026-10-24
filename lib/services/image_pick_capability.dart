import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

import 'crop_page.dart';

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
/// 移动端走系统图库 + 原生裁剪器，桌面端走文件选择 + 自建裁剪页，
/// 测试可以塞一个假实现。表单只负责把拿到的字节存好。
abstract interface class ImagePickCapability {
  /// [aspect] 为锁定的宽高比；null 表示自由裁剪。取消返回 null。
  ///
  /// 需要 [context] 是因为桌面端的裁剪页是 Flutter 页面。
  Future<PickedImage?> pickAndCrop(
    BuildContext context, {
    required double? aspect,
  });
}

/// 桌面平台（原生裁剪器不可用，需要自建裁剪页）。
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// 默认实现：
/// * 移动端 / Web：系统图库 + image_cropper 原生裁剪（与原行为一致）；
/// * 桌面：文件选择 + [FlutterCropPage] 自建裁剪页（image_cropper 无桌面实现）。
class DefaultImagePickCapability implements ImagePickCapability {
  const DefaultImagePickCapability();

  @override
  Future<PickedImage?> pickAndCrop(
    BuildContext context, {
    required double? aspect,
  }) async {
    if (_isDesktop) {
      return _pickAndCropDesktop(context, aspect: aspect);
    }

    final ImagePicker picker = ImagePicker();
    // 不传 imageQuality：GIF 若经 image_picker 重编码会丢失逐帧动画。
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return null;
    }
    final bool isGif = picked.name.toLowerCase().endsWith('.gif');

    // 裁剪仅 Android / iOS 可用（image_cropper 无 Web 实现）；
    // GIF 跳过裁剪：image_cropper 会重编码，导致动态 GIF 退化为静态帧。
    CroppedFile? cropped;
    if (!isGif && !kIsWeb) {
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

  /// 桌面端：文件选择器选图 → 自建裁剪页 → PNG 字节。
  Future<PickedImage?> _pickAndCropDesktop(
    BuildContext context, {
    required double? aspect,
  }) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final Uint8List? raw = result.files.single.bytes;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final bool isGif = result.files.single.name.toLowerCase().endsWith('.gif');
    // GIF 不裁剪（会丢帧），原样返回。
    if (isGif) {
      return PickedImage(bytes: raw, extension: '.gif');
    }
    if (!context.mounted) {
      return null;
    }
    final Uint8List? cropped = await showFlutterCropPage(
      context,
      source: raw,
      aspect: aspect,
    );
    if (cropped == null || cropped.isEmpty) {
      return null;
    }
    return PickedImage(bytes: cropped, extension: '.png');
  }
}
