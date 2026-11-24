/// 图片文件名的**格式与纯函数**：IO 端与 Web 端共用同一份。
///
/// `image_storage_io.dart` 与 `image_storage_stub.dart` 原本各写一遍
/// `_normalizeExt`（逐字相同），合并到这里，避免一端改了另一端忘。
library;

/// 图片扩展名归一化：统一带点、小写；给空时用 `.jpg`。
String normalizeImageExt(String? ext) {
  final String e = (ext == null || ext.isEmpty) ? '.jpg' : ext;
  return e.startsWith('.') ? e : '.$e';
}
