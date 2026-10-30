import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dna/services/crop_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_cropper/image_cropper.dart';

import 'card_crop_page.dart';

/// 移动端/桌面端裁剪实现：把字节写入临时文件，调起原生裁剪器，读回结果。
///
/// 默认把比例锁定到 [CropAspect]：1:1 / 16:9 / 9:16 是展示端硬约束，不允许在裁剪
/// 界面里改成别的比例（服务端按同一套比例强制校验，见 card_publish_service.py）。
/// 打开「自由剪图」后不再传比例、也不再锁（见 [FreeImageCrop]）。
Future<Uint8List?> openCropPage(
  BuildContext context, {
  required Uint8List sourceBytes,
  required CropAspect aspect,
}) async {
  // 在 await 前取好主题色，避免跨异步使用 BuildContext。
  final scheme = Theme.of(context).colorScheme;
  // 自由剪图：不传 aspectRatio（uCrop / TOCropViewController 即进入自由裁剪），
  // 同时解除 lockAspectRatio。注意这里必须在 await 之前读，保证与用户点击时的开关一致。
  final bool freeRatio = FreeImageCrop.enabled;
  // 桌面端没有原生裁剪器（image_cropper 只实现了 Android/iOS/Web），走自建裁剪页。
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    return showFlutterCropPage(
      context,
      source: sourceBytes,
      aspect: freeRatio ? null : aspect.ratio,
    );
  }

  final dir = await Directory.systemTemp.createTemp('dnaisland_crop');
  final file = File(
    '${dir.path}${Platform.pathSeparator}source_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(sourceBytes, flush: true);

  try {
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: freeRatio
          ? null
          : CropAspectRatio(ratioX: aspect.ratio, ratioY: 1),
      compressFormat: ImageCompressFormat.png,
      compressQuality: 92,
      uiSettings: <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle: '裁剪图片',
          toolbarColor: scheme.primary,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: !freeRatio,
          backgroundColor: Colors.black,
          // 刻意不传 initAspectRatio：插件的 Java 侧只要 aspectRatioPresets（默认非空）
          // 与 initAspectRatio 同时非空，就会调 setAspectRatioOptions 构建 uCrop 的比例菜单，
          // 用户能在菜单里换成别的比例，从而绕过 lockAspectRatio。
          // 传 null 会让整段逻辑跳过，裁剪界面根本不出现比例菜单。
        ),
        IOSUiSettings(
          title: '裁剪图片',
          // iOS 侧插件在收到 aspectRatio 后还会强制 aspectRatioPickerButtonHidden=YES、
          // resetAspectRatioEnabled=NO，这里显式写死避免误读为可解锁。
          // 自由剪图时反过来：不锁、允许改比例。
          aspectRatioLockEnabled: !freeRatio,
          resetAspectRatioEnabled: freeRatio,
        ),
        // WebUiSettings 需要 BuildContext 作为 web 裁剪器的宿主；此处为发起调用前
        // 构造配置，context 仍有效，忽略跨异步 lint。
        // ignore: use_build_context_synchronously
        WebUiSettings(context: context),
      ],
    );
    if (cropped == null) return null;
    return await cropped.readAsBytes();
  } catch (_) {
    return null;
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // 清理临时目录失败可忽略
    }
  }
}
