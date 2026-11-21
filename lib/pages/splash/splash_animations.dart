import 'package:flutter/material.dart';

import 'glass_logo_animation.dart';
import 'logo_draw_animation.dart';
import 'logo_painter.dart';

/// 一段开场动画的描述（数据驱动）。
///
/// 设置页的选项、启动时播哪段、播多久，全部来自 [kSplashAnimations] ——
/// 新增一种动画只改这个文件，不用再动设置声明、开关判断或启动逻辑。
class SplashAnimationSpec {
  const SplashAnimationSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.durationMs,
    required this.build,
  });

  /// 稳定 id：写进设置、存档与备份，**不能随文案改**。
  final String id;

  /// 设置里显示的选项名。
  final String label;

  /// 设置里的一句说明。
  final String description;

  /// 这段动画播多久（0 = 不播）。
  final int durationMs;

  /// 真正渲染 + 播完回调。
  /// 渲染这段动画。时长由表里的 durationMs 传进来，避免同一个数字写两处。
  final Widget Function(
    BuildContext context,
    VoidCallback onComplete,
    int durationMs,
  ) build;

  bool get enabled => durationMs > 0;
}

/// 「不播动画」的 id。
const String kSplashAnimationOffId = 'none';

/// 默认动画 id（与老版本行为一致：描边 + 填充 + 冲淡）。
const String kDefaultSplashAnimationId = 'logoDraw';

/// 全部可选的开场动画。新增动画只在这里追加一条：
/// * 设置页的选项列表由它生成；
/// * 启动时按 id 取 spec 播放；
/// * 存档里存的是 id，读不到就回退到默认。
const List<SplashAnimationSpec> kSplashAnimations = <SplashAnimationSpec>[
  SplashAnimationSpec(
    id: kDefaultSplashAnimationId,
    label: '描边绽放',
    description: '先勾出轮廓、填满，再放大淡出。',
    durationMs: 3200,
    build: _buildLogoDraw,
  ),
  SplashAnimationSpec(
    id: 'glassLogo',
    label: '液态玻璃',
    description: '玻璃里映着 logo，落一滴水再摊平。',
    durationMs: 1800,
    build: _buildGlassLogo,
  ),
  SplashAnimationSpec(
    id: 'zoom',
    label: '缩放淡入',
    description: '从略小处弹到位，轻快不拖沓。',
    durationMs: 1200,
    build: _buildZoom,
  ),
  SplashAnimationSpec(
    id: 'fade',
    label: '淡入',
    description: '最安静的一种，只做透明度过渡。',
    durationMs: 900,
    build: _buildFade,
  ),
  SplashAnimationSpec(
    id: kSplashAnimationOffId,
    label: '关闭动画',
    description: '启动直接进主界面。',
    durationMs: 0,
    build: _buildNone,
  ),
];

/// 按 id 取 spec；未知 id（改过配置/旧存档）回退到默认。
SplashAnimationSpec splashAnimationById(String id) {
  for (final SplashAnimationSpec spec in kSplashAnimations) {
    if (spec.id == id) return spec;
  }
  return kSplashAnimations.first;
}

Widget _buildLogoDraw(
  BuildContext context,
  VoidCallback onComplete,
  int durationMs,
) =>
    LogoDrawAnimation(durationMs: durationMs, onComplete: onComplete);

/// 缩放淡入在进度 [t]（0..1）时的缩放比。
///
/// 抽成纯函数是为了能被测试直接验算 —— 之前它和「淡入」几乎没差别，
/// 就是因为幅度只有 14% 且被二次缓动吃掉，肉眼看不出在放大。
double splashZoomScale(double t) =>
    0.45 + 0.55 * Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

/// 缩放淡入在进度 [t] 时的不透明度：前 15% 就把自己显出来，
/// 剩下的时间留给「变大」这件事被看见（否则透明度和缩放同时结束，
/// 观感又会退化成一次淡入）。
double splashZoomOpacity(double t) =>
    Curves.easeOut.transform((t / 0.15).clamp(0.0, 1.0));

/// 淡入在进度 [t] 时的不透明度（只做透明度，没有任何缩放）。
double splashFadeOpacity(double t) =>
    Curves.easeInOut.transform(t.clamp(0.0, 1.0));

Widget _buildGlassLogo(
  BuildContext context,
  VoidCallback onComplete,
  int durationMs,
) =>
    GlassLogoAnimation(durationMs: durationMs, onComplete: onComplete);

Widget _buildZoom(
  BuildContext context,
  VoidCallback onComplete,
  int durationMs,
) =>
    _SimpleLogoEntrance(
      durationMs: durationMs,
      onComplete: onComplete,
      builder: (double t) {
        // 透明度先跑完（前 45%），保证「看得见它在放大」；剩下的时间只做缩放，
        // 末尾用 easeOutBack 轻微过冲。缩放幅度取 0.55→1（原来 0.86→1 只有 14%
        // 的变化，在 120px 的 logo 上等于没动，看起来和「淡入」一模一样）。
        return Opacity(
          opacity: splashZoomOpacity(t),
          child: Transform.scale(
            scale: splashZoomScale(t),
            child: const _FilledLogo(),
          ),
        );
      },
    );

Widget _buildFade(
  BuildContext context,
  VoidCallback onComplete,
  int durationMs,
) =>
    _SimpleLogoEntrance(
      durationMs: durationMs,
      onComplete: onComplete,
      builder: (double t) => Opacity(
        opacity: splashFadeOpacity(t),
        child: const _FilledLogo(),
      ),
    );

Widget _buildNone(
  BuildContext context,
  VoidCallback onComplete,
  int durationMs,
) {
  // 兜底：正常路径下 main 不会挂这个页面；万一被挂上也立刻结束。
  WidgetsBinding.instance.addPostFrameCallback((_) => onComplete());
  return const SizedBox.shrink();
}

/// 已填充好的 logo（缩放/淡入两种动画共用）。
class _FilledLogo extends StatelessWidget {
  const _FilledLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: LogoPainter(drawProgress: 1, fillProgress: 1),
      ),
    );
  }
}

/// 通用的一小段「按进度画一帧」的动画外壳（缩放/淡入共用）。
class _SimpleLogoEntrance extends StatefulWidget {
  const _SimpleLogoEntrance({
    required this.durationMs,
    required this.onComplete,
    required this.builder,
  });

  final int durationMs;
  final VoidCallback onComplete;
  final Widget Function(double t) builder;

  @override
  State<_SimpleLogoEntrance> createState() => _SimpleLogoEntranceState();
}

class _SimpleLogoEntranceState extends State<_SimpleLogoEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.durationMs),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void didUpdateWidget(_SimpleLogoEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.durationMs == widget.durationMs) return;
    // 换了动画（时长不同）：旧控制器已经停在结束态，必须重建，否则新动画不播。
    _controller.dispose();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );
    _controller.forward().whenComplete(() {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) =>
          // 传**线性**进度：具体用哪条曲线由每段动画自己决定。
          // 以前在这里先 ease 一遍，builder 里再 ease 一次，等于二次缓动 ——
          // 动画前段几乎不动，观感直接退化成「淡入」。
          widget.builder(_controller.value),
    );
  }
}
