import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 用 Blob + <a download> 触发浏览器下载。
///
/// 返回是否成功触发；失败（浏览器拦下载等）返回 false，由调用方提示。
bool downloadBytes({
  required Uint8List bytes,
  required String fileName,
  required String mime,
}) {
  try {
    final web.Blob blob = web.Blob(
      <JSUint8Array>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mime),
    );
    final String url = web.URL.createObjectURL(blob);
    final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    anchor.click();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
