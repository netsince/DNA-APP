import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// 将项目内 PNG 图标设置为浏览器标签页 favicon。
///
/// 通过 base64 data URL 直接写入 `<link rel="icon">`，点击后即时生效。
Future<void> setBrowserFavicon(String assetPath) async {
  try {
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final String dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';

    final web.Document document = web.document;
    web.Element? link = document.querySelector('link[rel="icon"]');
    if (link == null) {
      final web.Element newLink = document.createElement('link');
      newLink.setAttribute('rel', 'icon');
      document.head?.append(newLink);
      link = newLink;
    }
    link.setAttribute('href', dataUrl);
  } catch (_) {
    // favicon 设置失败不影响应用使用。
  }
}
