// 端侧语音合成服务入口。
//
// 通过条件导出加载平台实现：
// - IO 平台（Android/iOS/桌面）：完整实现（ChatTTS + onnxruntime）
// - Web 平台：空实现（语音合成已置灰禁用）
//
// 由于 onnxruntime 依赖 dart:ffi，Web 编译时不能进入编译图，
// 因此必须通过条件导出隔离，否则 `flutter build web` 会失败。
export 'tts_service_stub.dart'
    if (dart.library.io) 'tts_service_io.dart';
