import 'dart:ui' show Color;

/// 液态玻璃开场动画的**编排层**：把时间映射成一组 uniform 数值。
///
/// 移植自 reactdrops 的 `liquid-glass-logo`（MIT）：那边用 five 条 Catmull-Rom
/// 关键帧曲线驱动，这里原样搬过来，只在 Dart 里算数——不碰渲染。
///
/// 这样拆的好处：动画节奏可以被单测覆盖（«某个时刻应该刚好定版» 这类断言），
/// 而着色器那边只负责「按这组数值画一帧」。

/// 总时长：前 [kGlassLogoHoldStart] 秒把玻璃长开并定版，之后**停在定版 ICON 上**，
/// 到点再进主界面。
///
/// 原组件是 1.8s（logo 模式），但那 1.8 秒里还塞了「第二滴落下来把 logo 吸走」的
/// 收尾，实测太快看不清、结尾也不好看。这里把收尾改成静止停留。
const double kGlassLogoDuration = 2.6;

/// 定版时刻：从这一刻起画面不再变化。
const double kGlassLogoHoldStart = 1.45;

/// 关键帧表：`[秒, 值]`，按时间升序；用 Catmull-Rom 穿过（不是缓动函数）。
typedef KeyTrack = List<List<double>>;

/// 平滑插值（与原实现同一个公式：不等距 Catmull-Rom）。
double track(KeyTrack keys, double t) {
  if (t <= keys.first[0]) return keys.first[1];
  final List<double> last = keys.last;
  if (t >= last[0]) return last[1];
  int i = 0;
  while (t > keys[i + 1][0]) {
    i++;
  }
  final double t1 = keys[i][0];
  final double v1 = keys[i][1];
  final double t2 = keys[i + 1][0];
  final double v2 = keys[i + 1][1];
  final List<double>? prev = i > 0 ? keys[i - 1] : null;
  final List<double>? next = i + 2 < keys.length ? keys[i + 2] : null;
  final double t0 = prev?[0] ?? (t1 - (t2 - t1));
  final double v0 = prev?[1] ?? v1;
  final double t3 = next?[0] ?? (t2 + (t2 - t1));
  final double v3 = next?[1] ?? v2;
  final double span = t2 - t1;
  final double m1 = ((v2 - v0) / (t2 - t0)) * span;
  final double m2 = ((v3 - v1) / (t3 - t1)) * span;
  final double x = (t - t1) / span;
  final double x2 = x * x;
  final double x3 = x2 * x;
  return (2 * x3 - 3 * x2 + 1) * v1 +
      (x3 - 2 * x2 + x) * m1 +
      (-2 * x3 + 3 * x2) * v2 +
      (x3 - x2) * m2;
}

double smooth(double from, double to, double value) {
  final double x = ((value - from) / (to - from)).clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// 玻璃里那份 logo 相对静置尺寸的大小：先被年轻液滴放大，再收敛回 1.0，
/// 最后被第二滴吸进去。与画面内容无关，纯编排。
const KeyTrack artworkScale = <List<double>>[
  <double>[0.12, 1.4],
  <double>[0.33, 1.45],
  <double>[0.46, 1.44],
  <double>[0.63, 1.33],
  <double>[0.79, 1.24],
  <double>[0.96, 1.2],
  <double>[1.13, 1.11],
  <double>[1.25, 1.0],
  <double>[1.335, 0.865],
  <double>[1.376, 0.81],
  <double>[1.418, 0.735],
  <double>[1.46, 0.41],
];

/// 第二滴：半径、核心半径、沿半径的拉伸、核心中心（负值反向）、边缘放大率。
const KeyTrack dropRadius = <List<double>>[
  <double>[1.46, 0.32], <double>[1.55, 0.36], <double>[1.67, 0.49],
  <double>[1.75, 0.52], <double>[1.84, 0.56], <double>[1.92, 0.68],
  <double>[2.0, 0.88], <double>[2.15, 0.95], <double>[2.4, 1.06],
  <double>[2.95, 1.3],
];
const KeyTrack dropCore = <List<double>>[
  <double>[1.46, 1.5], <double>[1.84, 1.5], <double>[1.92, 0.55],
  <double>[2.0, 0.6], <double>[2.09, 0.68], <double>[2.17, 0.78],
  <double>[2.3, 0.85], <double>[2.5, 0.9], <double>[2.75, 0.93],
  <double>[2.95, 0.97], <double>[3.02, 1.03],
];
const KeyTrack dropStretch = <List<double>>[
  <double>[1.46, 0.3], <double>[1.84, 0.3], <double>[2.0, 0.25],
  <double>[2.1, 0.2], <double>[2.2, 0.2], <double>[2.4, 0.25],
  <double>[2.7, 0.3], <double>[2.85, 0.45], <double>[2.95, 0.8],
  <double>[3.02, 1],
];
const KeyTrack dropCenter = <List<double>>[
  <double>[1.46, -0.6], <double>[1.6, -0.5], <double>[1.75, -0.3],
  <double>[1.8, 0.4], <double>[1.84, 1],
];
const KeyTrack dropMagnify = <List<double>>[
  <double>[1.46, 1.5], <double>[1.6, 1.5], <double>[1.75, 2.2],
  <double>[1.84, 1.4], <double>[1.92, 1.2], <double>[2.0, 1.05],
  <double>[2.1, 1],
];

/// 某一帧要交给着色器的一组数值（对应原实现的 uniform 集合）。
class GlassLogoFrame {
  const GlassLogoFrame({
    required this.time,
    required this.settle,
    required this.artScale,
    required this.drop,
    required this.dropLens,
    required this.dropWave,
    required this.settleWaves,
    required this.dropOpacity,
    required this.unitPx,
  });

  /// 裁剪到 [0, kGlassLogoDuration] 后的时间。
  final double time;

  /// 0→1：玻璃「定版」进度（1.16–1.40s 之间完成）。
  final double settle;

  /// logo 在玻璃里的缩放（见 [artworkScale]）。
  final double artScale;

  /// uDrop：(半径, 核心半径, 拉伸, 核心中心)。
  final List<double> drop;

  /// uDropLens：(边缘放大, 核心曲线指数, 涟漪振幅, 涟漪波长)。
  final List<double> dropLens;

  /// uDropWave：(涟漪相位, 内圈淡出, 外圈振幅, 保留)。
  final List<double> dropWave;

  /// 涟漪收尾包络（2.85–3.02s 归零；logo 模式在 1.8s 定版，看不到这段）。
  final double settleWaves;

  /// 第二滴的整体可见度：1.46 之前为 0（半径虽非零但看不见），1.56 之后满。
  final double dropOpacity;

  /// 玻璃基准像素（logoSize × scale）。
  final double unitPx;
}

/// 把秒数换算成一组 uniform。
///
/// [unitPx] 是玻璃的基准尺寸（逻辑像素）；[finalLogoScale] 是定版后 logo 的
/// 缩放；[dropStrength] 放大/削弱第二滴的位移。
GlassLogoFrame glassLogoFrameAt(
  double seconds, {
  required double unitPx,
  required double finalLogoScale,
  required double dropStrength,
  bool showDrop = false,
}) {
  final double seq = seconds.clamp(0.0, kGlassLogoDuration).toDouble();
  // 定版之后时间冻在 1.8：着色器那边就是「停在最后一帧」，不再做收尾动画。
  final double t = seq.clamp(0.0, 1.8).toDouble();
  final double settle = ((seq - 1.16) / (1.4 - 1.16)).clamp(0.0, 1.0).toDouble();
  final double settleWaves = 1 - smooth(2.85, 3.02, t);
  // 第二滴的尺度：原实现在纯 logo 模式取玻璃基准的 0.3 倍，视觉上太小（只剩
  // 一个白点），这里放大到 0.5 倍，让「落一滴」这件事看得见。
  final double reach = unitPx * 0.5;
  // 定版：1.13→1.28 过渡到 finalLogoScale，**之后不再走 artworkScale**。
  // 那条曲线是为 wordmark 设计的（logo 被吸进文字滴、缩到 0.41），套在纯 logo
  // 上会在 1.46 后出现「logo 突然缩小 + 一圈巨大重影」，很难看。
  final double artSettle = smooth(1.13, 1.28, seq);
  final double artScale = seq > 1.13
      ? track(artworkScale, 1.13) * (1 - artSettle) + finalLogoScale * artSettle
      : track(artworkScale, t);
  return GlassLogoFrame(
    time: t,
    settle: settle,
    artScale: artScale,
    drop: <double>[
      reach * track(dropRadius, t),
      reach * track(dropCore, t),
      track(dropStretch, t).clamp(0.02, 1.0).toDouble(),
      1 + (track(dropCenter, t) - 1) * dropStrength,
    ],
    dropLens: <double>[
      1 + (track(dropMagnify, t) - 1) * dropStrength,
      2 + 4 * smooth(1.74, 1.84, t),
      unitPx *
          (0.009 *
                      _expNeg((t - 1.46).clamp(0.0, 1e9) / 0.5) *
                      (1 - smooth(1.85, 1.95, t)) +
                  0.012 * smooth(2.2, 2.4, t)) *
          settleWaves,
      unitPx * (0.07 + (0.03 - 0.07) * smooth(1.9, 2.4, t)),
    ],
    dropWave: <double>[
      (t - 1.45) * 42,
      1 - smooth(1.85, 2.0, t),
      2 *
          (0.12 +
                  1.6 * smooth(1.86, 2.0, t) -
                  0.9 * smooth(2.25, 2.5, t)) *
              settleWaves,
      0,
    ],
    settleWaves: settleWaves,
    dropOpacity: showDrop ? smooth(1.46, 1.56, t) * 0.8 : 0,
    unitPx: unitPx,
  );
}

double _expNeg(double x) {
  // 与原实现一致的 exp(-x)，单独抽出来避免 dart:math 依赖出现在测试热路径。
  return 1 / _ePow(x);
}

double _ePow(double x) {
  // exp 的泰勒展开足够（x 在 0..40 内，用于一个已经衰减到 0 的振幅）。
  double sum = 1;
  double term = 1;
  for (int i = 1; i < 24; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

/// 玻璃/墨色配置：对应原实现的 tuning（只保留我们开场用得到的部分）。
class GlassLogoTuning {
  const GlassLogoTuning({
    this.logoColor = const Color(0xFFFFFFFF),
    this.tileColor = const Color(0xFF060C18),
    this.background = const Color(0xFF1A1A1A),
    this.logoSize = 260,
    this.logoScale = 0.72,
    this.finalLogoScale = 0.95,
    this.depth = 1.15,
    this.dispersion = 1.8,
    this.relief = 3,
    this.caustics = 3,
    this.highlights = 3,
    this.bloom = 0.6,
    this.dropSize = 0.32,
    this.dropStrength = 1.35,
    this.echoTint = 1,
    this.innerWallFocus = 0,
    this.decay = 2.5,
    this.tileEnabled = true,
    this.showDrop = false,
  });

  final Color logoColor;
  final Color tileColor;
  final Color background;

  /// 玻璃基准尺寸（逻辑像素）。
  final double logoSize;

  /// logo 在玻璃里的初始缩放。
  final double logoScale;

  /// 定版后的缩放。
  final double finalLogoScale;

  final double depth;
  final double dispersion;
  final double relief;
  final double caustics;
  final double highlights;
  final double bloom;
  final double dropSize;
  final double dropStrength;
  final double echoTint;
  final double innerWallFocus;
  final double decay;
  final bool tileEnabled;

  /// 结尾是否要「落一滴水」（默认关：落完那一下不优雅，停在定版 ICON 更好）。
  final bool showDrop;

  /// 玻璃基准像素（原实现的 uUnit = logoSize * scale，这里 scale 恒为 1）。
  double get unitPx => logoSize;
}
