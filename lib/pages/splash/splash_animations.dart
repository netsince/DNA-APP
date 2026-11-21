import 'package:flutter/material.dart';

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
  final Widget Function(BuildContext context, VoidCallback onComplete) build;

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

Widget _buildLogoDraw(BuildContext context, VoidCallback onComplete) =>
    LogoDrawAnimation(onComplete: onComplete);

Widget _buildZoom(BuildContext context, VoidCallback onComplete) =>
    _SimpleLogoEntrance(
      durationMs: 1200,
      onComplete: onComplete,
      builder: (double t) => Opacity(
        opacity: t.clamp(0.0, 1.0).toDouble(),
        child: Transform.scale(
          // 0.86 → 1，带一点回弹，比线性缩放更有生气。
          scale: 0.86 + 0.14 * Curves.easeOutBack.transform(t),
          child: const _FilledLogo(),
        ),
      ),
    );

Widget _buildFade(BuildContext context, VoidCallback onComplete) =>
    _SimpleLogoEntrance(
      durationMs: 900,
      onComplete: onComplete,
      builder: (double t) => Opacity(
        opacity: t.clamp(0.0, 1.0).toDouble(),
        child: const _FilledLogo(),
      ),
    );

Widget _buildNone(BuildContext context, VoidCallback onComplete) {
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
          widget.builder(Curves.easeOut.transform(_controller.value)),
    );
  }
}
