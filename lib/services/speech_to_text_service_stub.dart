import 'dart:typed_data';

import '../models/voice_models.dart';

/// 离线语音转文字服务的 Web 空实现。
///
/// Web 平台不支持 sherpa-onnx（dart:ffi）与原生录音，语音输入在 UI 层
/// 已通过 [PlatformCapabilities] 置灰禁用。此 stub 保证编译通过并提供
/// 安全的默认行为（始终返回 false / 空串，不触碰任何原生 API）。
class SpeechToTextService {
  SpeechToTextService._();

  static final SpeechToTextService instance = SpeechToTextService._();

  /// 采样率（与 IO 实现保持一致，避免调用方依赖差异）。
  static const int sampleRate = 16000;

  /// 实时中间识别结果流（Web 上恒为空）。
  Stream<String> get partial => const Stream<String>.empty();

  bool get isRecording => false;

  bool get isInitialized => false;

  Future<void> ensureInitialized(String modelDir) async {}

  Future<bool> start() async => false;

  Future<String> stop() async => '';

  Future<void> cancel() async {}

  void dispose() {}
}

/// 将 16-bit PCM 字节（小端）转换为 Float32 采样（纯算法，与平台无关）。
Float32List convertBytesToFloat32(Uint8List bytes) {
  final ByteData byteData = ByteData.sublistView(bytes);
  final int length = bytes.length ~/ 2;
  final Float32List float32 = Float32List(length);
  for (int i = 0; i < length; i++) {
    final int intSample = byteData.getInt16(i * 2, Endian.little);
    float32[i] = intSample / 32768.0;
  }
  return float32;
}

/// 根据 id 取得对应模型选项的便捷函数（供 UI 使用）。
VoiceModelOption resolveVoiceModel(String id) => voiceModelById(id);
