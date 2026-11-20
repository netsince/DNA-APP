import 'dart:typed_data';

/// 非 Web 平台没有这个东西（调用方本来就走文件分享/保存对话框）。
bool downloadBytes({
  required Uint8List bytes,
  required String fileName,
  required String mime,
}) {
  return false;
}
