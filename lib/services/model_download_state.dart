import 'package:flutter/foundation.dart';

/// 端侧模型下载中的**唯一**状态源（语音合成与语音识别共用）。
///
/// ## 为什么需要它
///
/// 下载期间要禁掉「切换识别模型」「切换下载源」这类选项 —— 否则用户中途换源，
/// 下载还在按旧源跑，完成后就绪标记会与当前选择对不上。这两项在声明层，
/// 下载状态却在 `SettingAction` 的自绘控件里，所以状态必须提到能被两边看见的地方。
///
/// ## 单一写入口
///
/// 只有 [begin] / [end] 能改它，且必须成对（用 try/finally）。用计数而不是
/// 布尔：两个下载组件同时存在时，先结束的那个不能把另一个的状态抹掉。
class ModelDownloads {
  ModelDownloads._();

  static final ValueNotifier<int> _active = ValueNotifier<int>(0);

  /// 供页面监听：值为正在进行的下载数。
  static ValueListenable<int> get notifier => _active;

  static bool get isDownloading => _active.value > 0;

  /// 开始一次下载。必须与 [end] 配对。
  static void begin() => _active.value++;

  /// 结束一次下载（幂等下限保护，避免多减成负数）。
  static void end() {
    if (_active.value > 0) _active.value--;
  }
}
