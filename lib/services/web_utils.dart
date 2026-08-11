// Web 平台工具入口。
//
// 通过条件导出加载平台实现：
// - IO 平台：空实现
// - Web 平台：浏览器 favicon 等 DOM 操作
export 'web_utils_stub.dart'
    if (dart.library.js_interop) 'web_utils_web.dart';
