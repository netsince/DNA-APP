// 离线语音输入服务入口。
//
// 通过条件导出加载平台实现：
// - IO 平台（Android/iOS/桌面）：完整实现（sherpa-onnx + record）
// - Web 平台：空实现（语音输入已置灰禁用）
//
// 由于 sherpa_onnx 依赖 dart:ffi，Web 编译时不能进入编译图，
// 因此必须通过条件导出隔离，否则 `flutter build web` 会失败。
export 'speech_to_text_service_stub.dart'
    if (dart.library.io) 'speech_to_text_service_io.dart';
