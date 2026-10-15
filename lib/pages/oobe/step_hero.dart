import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/brand_icon.dart';

/// 步骤头部的英雄位：一块会「动起来」的图标。
///
/// ## 为什么只播一次，不做循环
///
/// 常驻循环动画会让 `pumpAndSettle()` 永远等不到静止 —— 测试会以「超时」的形式
/// 失败，而报错信息完全不指向动画，非常难查。所以这里的契约是：
/// **进入这一步、或换了服务商时，播一次就停**。
///
/// 系统开了「减少动态效果」（[MediaQueryData.disableAnimations]）时直接跳到终态。
///
/// ## 素材
///
/// * API 步骤传 [providerId]，画当前服务商的**真实品牌标**，并且切换服务商时
///   重新描边生长一次 —— 动效在传达状态，不是纯装饰；
/// * 其余步骤用 [icon]，走同一套时长、缓动与容器。
///
/// ## 尺寸
///
/// [size] 由父级按可用高度算好传进来（见 oobe_page 的 heroSizeFor）。
/// 屏幕矮就画小一点，但**不隐藏** —— 完全消失会让每一步看起来一样平。
class StepHero extends StatefulWidget {
  const StepHero({
    super.key,
    required this.stepIndex,
    required this.icon,
    required this.size,
    this.providerId,
  });

  /// 步骤序号；变化时重播。
  final int stepIndex;

  /// 没有品牌标时用的图标。
  final IconData icon;

  /// 容器边长。
  final double size;

  /// 非空时改用该服务商的真实品牌标；变化时重播。
  final String? providerId;

  @override
  State<StepHero> createState() => _StepHeroState();
}

class _StepHeroState extends State<StepHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late final Animation<double> _scale;
  late final Animation<double> _turn;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.transform,
    );
    final CurvedAnimation curve = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.emphasized,
    );
    _progress = curve;
    _scale = Tween<double>(begin: 0.74, end: 1).animate(curve);
    _turn = Tween<double>(begin: -0.12, end: 0).animate(curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在这里播第一次：didChangeDependencies 会因为 MediaQuery 变化再进来，
    // 每次都重播会很吵。
    if (!_started) {
      _started = true;
      _play();
    }
  }

  @override
  void didUpdateWidget(StepHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepIndex != widget.stepIndex ||
        oldWidget.providerId != widget.providerId) {
      _play();
    }
  }

  void _play() {
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double markSize = widget.size * 0.56;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(widget.size * 0.28),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? _) {
              // 注意：品牌标必须在这里构建 —— 放进 AnimatedBuilder 的 child
              // 参数只会构建一次，progress 就不会跟着动画走了。
              final Widget mark = widget.providerId == null
                  ? Icon(
                      widget.icon,
                      size: markSize,
                      color: cs.onPrimaryContainer,
                    )
                  : BrandIcon(
                      id: widget.providerId!,
                      size: markSize,
                      color: cs.onPrimaryContainer,
                      progress: _progress.value,
                    );
              return Transform.rotate(
                angle: _turn.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Opacity(opacity: _progress.value, child: mark),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
