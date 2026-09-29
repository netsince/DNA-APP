import 'package:flutter/foundation.dart';

/// 平台能力门控：Web 上无法支持的功能在此统一声明。
///
/// 被砍掉（置灰禁用）的功能入口在 UI 层通过这里判定：
/// Web 端一律不可用（置灰），移动端 / 桌面端不受影响。
abstract class PlatformCapabilities {
  PlatformCapabilities._();

  /// 离线语音输入（sherpa-onnx + record）。
  static bool get voiceInputSupported => !kIsWeb;

  /// 端侧语音合成（ChatTTS + onnxruntime）。
  static bool get ttsSupported => !kIsWeb;

  /// 生物识别 / 设备凭证认证（local_auth）。
  static bool get biometricAuthSupported => !kIsWeb;

  /// 桌面端（Windows / macOS / Linux）。
  ///
  /// 用于按桌面习惯调整布局与密度:桌面用鼠标指针、屏幕更宽,
  /// 控件可以更紧凑、内容列可以限宽居中。
  static bool get isDesktop {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }
}
