// 离线语音输入服务入口。
//
// IO（桌面 / 移动端）走 sherpa-onnx 流式识别；Web 没有 dart:ffi 与原生录音，
// 落到 stub（始终返回 false / 空串，UI 层已按平台置灰）。
export 'speech_to_text_service_io.dart'
    if (dart.library.js_interop) 'speech_to_text_service_stub.dart';
