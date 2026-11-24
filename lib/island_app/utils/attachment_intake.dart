import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 社区端图片附件读取的统一入口。
///
/// 这套逻辑原本在 island 端抄了十几份：
/// - **扩展名 → MIME** 5 份（`tickets_page` 一个文件里就有 2 份），
///   缺省值还不一样（有的 png、有的 jpeg）；
/// - **选图** 4 份（都是 `pickImage(maxWidth: 1280, maxHeight: 1280, quality: 82)`
///   + 防重入 + 失败提示）；
/// - **拼 data URL** 4 份（`'data:$mime;base64,${base64Encode(bytes)}'`）；
/// - **解 data URL** 2 份。
///
/// 这里收口后，各处只传"差异"（缺省 MIME、尺寸上限），不再各写一遍。

/// 扩展名 → MIME。`ext` 可以带点（`.png`）也可以不带。
String mimeForExtension(String ext, {String fallback = 'image/png'}) {
  final String e = ext.toLowerCase().replaceAll('.', '');
  switch (e) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'png':
      return 'image/png';
    default:
      return fallback;
  }
}

/// 文件名/路径 → MIME（取最后一个 `.` 之后的部分）。
String mimeForFileName(String name, {String fallback = 'image/png'}) {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return fallback;
  return mimeForExtension(name.substring(dot + 1), fallback: fallback);
}

/// 文件名/路径 → 扩展名（不带点）。
String extensionOfFileName(String name, {String fallback = 'png'}) {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return fallback;
  return name.substring(dot + 1).toLowerCase();
}

/// 扩展名 + 字节 → base64 data URL（后端约定的内联格式）。
String dataUrlFor({required String ext, required List<int> bytes}) =>
    'data:${mimeForExtension(ext)};base64,${base64Encode(bytes)}';

/// data URL → 字节。解析失败、或不是 base64 data URL 时返回 null。
Uint8List? decodeDataUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final int comma = url.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(url.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// 从相册选一张图片。
///
/// 统一的上限（1280 长边 / 质量 82）来自原来四份实现里最大公倍数的那套：
/// 图片最终都会在服务端再压成 WebP，本地先压一次只是省上行带宽。
Future<XFile?> pickImageFile(
  ImagePicker picker, {
  ImageSource source = ImageSource.gallery,
  double maxSide = 1280,
  int quality = 82,
}) => picker.pickImage(
  source: source,
  maxWidth: maxSide,
  maxHeight: maxSide,
  imageQuality: quality,
);
