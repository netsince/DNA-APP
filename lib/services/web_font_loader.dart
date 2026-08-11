import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:http/http.dart' as http;

/// 网页版中文字体加载器（仅 Web 生效）。
///
/// 原因：Flutter Web 默认使用 CanvasKit 渲染，文字在画布上绘制，
/// 不走 CSS font-family，也拿不到用户本地字体数据，必须自行加载
/// 单个完整的中文字体文件字节（Google Fonts 的 unicode-range 分片
/// 对 Flutter 无效，因此这里使用 fontsource 的简体中文单文件 woff2）。
///
/// 加载策略：按 [fallbackUrls] 顺序依次尝试，任一成功即停止；
/// 全部失败则使用 Flutter 默认字体（不注册任何 family）。
class WebFontLoader {
  WebFontLoader._();

  /// 中文字体 family 名。
  static const String familyName = 'Noto Sans SC';

  /// 候选字体文件 URL（按优先级排列）。
  static const List<String> fallbackUrls = <String>[
    'https://fastly.jsdelivr.net/npm/@fontsource/noto-sans-sc@5.3.0/files/noto-sans-sc-chinese-simplified-400-normal.woff2',
    'https://cdn.jsdelivr.net/npm/@fontsource/noto-sans-sc@5.3.0/files/noto-sans-sc-chinese-simplified-400-normal.woff2',
  ];

  /// 加载字体，失败静默（回退默认字体）。
  static Future<void> load() async {
    if (!kIsWeb) return;
    for (final String url in fallbackUrls) {
      try {
        final http.Response resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) continue;
        final FontLoader loader = FontLoader(familyName)
          ..addFont(Future<ByteData>.value(ByteData.sublistView(resp.bodyBytes)));
        await loader.load();
        return;
      } catch (_) {
        // 该地址不可用，尝试下一个。
      }
    }
  }
}
