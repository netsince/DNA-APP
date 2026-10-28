import 'package:flutter/widgets.dart';

/// 全局字号档位。
///
/// 一个旋钮管全应用（含社区）：**0 = 跟随系统**，1..5 从最小到最大递增。
/// 0 这一档不覆盖任何东西 —— 交给系统无障碍字号，也就是本功能出现之前的行为；
/// 选了 1..5 就是**绝对倍率**（不再乘系统字号），否则「系统 1.5 × 应用 1.3」
/// 会得出 1.95 这种几乎必炸的组合。
///
/// 倍率作用在 `MediaQuery.textScaler` 上，因此对**所有**文字生效：
/// 主题里的 11 个槽位、`AppFontSize` 令牌、以及历史遗留的裸 fontSize。
/// 它**不**缩放布局尺寸（间距、图标、固定高度）—— 那些要么跟内容自适应，
/// 要么在字号巡检时单独放宽。
abstract final class AppFontScale {
  /// 跟随系统（不覆盖）。
  static const int followSystem = 0;

  /// 最大档位（滑块上端）。
  static const int maxStep = 5;

  /// 各档位对应的绝对倍率；null = 跟随系统。
  ///
  /// 为什么是这 5 档：0.85 用来「一屏塞更多」（小屏手机 / 桌面小窗），
  /// 1.0 是设计基准（也是 DESIGN_SPEC 里字号的原始像素），
  /// 1.15 / 1.30 / 1.45 逐级加约 13%，中间不出现「跳一格就变一个尺寸」的断层。
  static const List<double?> _scales = <double?>[
    null, // 0 跟随系统
    0.85,
    1.0,
    1.15,
    1.30,
    1.45,
  ];

  /// 档位名（滑块标签与设置项右侧当前值）。
  static const List<String> labels = <String>[
    '跟随系统',
    '小',
    '标准',
    '大',
    '特大',
    '超大',
  ];

  /// 把任意（含脏数据）档位夹到合法范围。
  static int clampStep(int step) {
    if (step < followSystem) return followSystem;
    if (step > maxStep) return maxStep;
    return step;
  }

  /// 档位对应的倍率；跟随系统时返回 null。
  static double? scaleOf(int step) => _scales[clampStep(step)];

  ///最终有效倍率的上下限（系统 ×应用之后封顶）。
  ///
  ///下限0.8：再小中文就看不清了；系统本来就调得小、应用又选「小」也不会跌破。
  ///上限2.0：系统2.0 ×应用1.45会得出2.9，那种字号下任何固定高度容器都会炸。
  static const double minEffectiveScale = 0.8;
  static const double maxEffectiveScale = 2.0;

  ///把「系统字号」与「应用档位」合成最终倍率。
  ///
  /// **组合而不是替换**：MediaQuery.textScaler是系统的无障碍通道，应用内档位是
  ///设计偏好，两者语义不同，通用做法是相乘（微信、浏览器都是这个模型）。早先的
  ///实现是「1..5档直接覆盖系统值」，结果用户系统已放大1.5、应用再选「超大」，
  ///得到的反而比系统还小 ——在无障碍上说不通。
  ///
  /// [systemFactor]是系统倍率（以正文为基准线性化后的值）；非法值按1.0处理。
  static double resolveScale({
    required int step,
    required double systemFactor,
  }) {
    final double app = scaleOf(step) ?? 1.0;
    final double system = systemFactor > 0 ? systemFactor : 1.0;
    final double total = app * system;
    if (total < minEffectiveScale) return minEffectiveScale;
    if (total > maxEffectiveScale) return maxEffectiveScale;
    return total;
  }

  /// 档位名；越界自动夹取（旧备份 / 手改偏好文件都不会崩）。
  static String labelOf(int step) => labels[clampStep(step)];

  /// 档位对应的 TextScaler；跟随系统时返回 null（调用方应原样放行）。
  static TextScaler? textScalerOf(int step) {
    final double? scale = scaleOf(step);
    return scale == null ? null : TextScaler.linear(scale);
  }
}
