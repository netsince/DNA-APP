/// 浏览器里的文件下载（只在 Web 上有实现，其它平台是 no-op）。
///
/// 为什么单独抽一层：导出 zip 时桌面/手机走临时文件 + 分享，Web 只能靠
/// Blob + <a download>；把平台差异收在这里，调用方不用写 if (kIsWeb) 分支。
library;
export 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart';
