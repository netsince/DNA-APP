import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'auth_image.dart';

/// 把社区里的图片**保存成 PNG**，落到用户找得到的地方。
///
/// ## 为什么改
///
/// 原实现是把服务端返回的字节**原样（WebP）写进系统临时目录**：
/// * 相册看不到 —— 临时目录不在媒体库里，手机上根本翻不到；
/// * 文件名是随机临时名，就算找到了也认不出是哪张；
/// * WebP 在部分相册/图片应用里直接显示不出来。
/// 用户反馈「保存完就找不着了，很麻烦」。
///
/// ## 现在
///
/// * **WebP → PNG**：相册/图片应用对 WebP 的支持并不普遍，PNG 到处都能看。
///   转码放在 isolate 里做（[compute]），不卡界面；
/// * **落点**：走系统「保存到…」对话框 —— Android 是 SAF（**默认就在 Download 目录**），
///   iOS 是「文件」，Web 等同于浏览器下载，桌面是选路径。用户能自己挑位置，
///   存完相册/文件应用立刻能看到。这样也**不需要任何存储权限**：
///   Android 11+ 分区存储下，用文件路径直接写公共 Download 目录会失败，
///   SAF 才是正路；
/// * 文件名取提示词/卡名，便于辨认。
///
/// 返回是否真的保存了：用户取消返回 false（不弹错误），失败会提示。
Future<bool> saveImageAsPng(
  BuildContext context, {
  required String url,
  required String baseName,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final Uint8List raw = await fetchAuthImageBytes(url);
    final Uint8List png = await compute(pngBytesFrom, raw);
    final String? saved = await _savePngBytes(png, pngFileName(baseName));
    if (saved == null) return false; // 用户取消：不提示错误
    // Android 的 SAF 回的是 content:// URI，直接摆给用户看没意义；有真实路径才显示路径。
    messenger.showSnackBar(
      SnackBar(content: Text(saved.contains('://') ? '已保存到你选择的位置' : '已保存：$saved')),
    );
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    return false;
  }
}

/// 任意图片字节 → PNG 字节（WebP/JPEG/PNG 都认）。
///
/// 解码失败就**原样返回**，绝不把图片弄丢（宁可格式不对，也不能保存出 0 字节）。
/// 顶层函数，供 [compute] 在 isolate 里调用。
Uint8List pngBytesFrom(Uint8List bytes) {
  try {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    return img.encodePng(decoded);
  } catch (_) {
    return bytes;
  }
}

/// 由提示词/卡名生成保存用的 PNG 文件名。
///
/// 去掉文件名里不安全的字符（保留中文、字母数字、下划线、连字符），最长 30 字符，
/// 空的话兜底 `artwork.png`。
String pngFileName(String baseName) {
  // 先 trim 再替换：否则纯空格的名字会变成 "__" 而不是走兜底。
  final String trimmedInput = baseName.trim();
  final String safe =
      trimmedInput.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
  final String trimmed = safe.length > 30 ? safe.substring(0, 30) : safe;
  return '${trimmed.isEmpty ? 'artwork' : trimmed}.png';
}

/// 弹系统保存对话框并写入字节；用户取消返回 null。
Future<String?> _savePngBytes(Uint8List bytes, String fileName) async {
  // 移动端与 Web：必须带 bytes —— file_picker 在 Android/iOS 上要求如此，
  // 它会弹系统保存对话框（Android 走 SAF，默认落到 Download）并把字节写进去。
  // 注意顺序：kIsWeb 必须在前，Web 上访问 Platform 会抛异常。
  if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
    return FilePicker.platform.saveFile(
      dialogTitle: '保存图片到…',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: <String>['png'],
      bytes: bytes,
    );
  }

  // 桌面端：先选保存路径，再自己写字节（与项目里导出文件的策略一致）。
  final String? target = await FilePicker.platform.saveFile(
    dialogTitle: '保存图片到…',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: <String>['png'],
  );
  if (target == null) return null;
  final String path =
      target.toLowerCase().endsWith('.png') ? target : '$target.png';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
