import 'package:flutter/material.dart';

import '../theme/font_scale.dart';
import '../theme/tokens.dart';

/// 把「字号档位」平滑地接到 [MediaQuery.textScaler] 上。
///
/// 为什么需要它：档位是离散的（0 跟随系统 / 1..5），直接换值等于整棵树
/// 立刻按新字号重排 —— 观感就是「字突然跳一下」。这里把倍率从旧值插值到
/// 新值，字是「长」过去的。
///
/// 三条纪律：
///
/// 1. **静止在 0 档（跟随系统）时不留任何覆盖**。系统字号是非线性的
///    （Android 14 起按字号分段放大），用一个 linear 近似去顶掉它属于
///    越权：只看 14px 算出来的倍率，套到 24px 上就不是系统本来给的值了。
///    所以只有「动画进行中」才临时接管，落地后立刻交还。
/// 2. **动画只在档位变化时发生**，不参与任何常态渲染 —— 常态下本组件
///    要么原样放行 child，要么只包一层固定值的 MediaQuery。
/// 3. 系统开了「减少动态效果」时直接跳到终值（无障碍设置优先）。
class AnimatedFontScale extends StatefulWidget {
  const AnimatedFontScale({super.key, required this.step, required this.child});

  /// 当前档位（0 跟随系统，1..5 从最小到最大）。
  final int step;

  final Widget child;

  @override
  State<AnimatedFontScale> createState() => _AnimatedFontScaleState();
}

class _AnimatedFontScaleState extends State<AnimatedFontScale>
    with SingleTickerProviderStateMixin {
  /// 300ms：比 "fast"(200ms) 慢一档 —— 字号变化是**整屏重排**，200ms 会显得
  /// 像闪一下；再慢又拖沓。配合 easeOutCubic：先快后缓，像"长"到位。
  late final AnimationController _drive = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );

  /// 系统字号换算出的倍率（以正文 14px 为基准线性化）。
  double _system = 1.0;

  /// 系统是否要求减少动态效果。
  bool _reduceMotion = false;

  /// 是否正在（或已经）接管 textScaler。
  bool _override = false;

  /// 插值区间。
  double _from = 1.0;
  double _to = 1.0;

  @override
  void initState() {
    super.initState();
    final double? fixed = AppFontScale.scaleOf(widget.step);
    _override = fixed != null;
    _from = _to = fixed ?? 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _system = _systemFactor(context);
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(AnimatedFontScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) {
      _retarget();
    }
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  /// 以正文为基准把系统 [TextScaler] 线性化。
  double _systemFactor(BuildContext context) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    return scaler.scale(AppFontSize.body) / AppFontSize.body;
  }

  /// 目标倍率：固定档位用它自己的值；0 档回到系统值。
  ///目标倍率 =系统倍率 ×档位倍率（0档时档位倍率视作1.0），再按上下限封顶。
  ///
  ///这只是「动画要滚到的值」：0档静止时本组件不接管（见 _retarget），系统那个
  ///可能是非线性的原始 scaler会原样透传，不会被这里的线性近似顶掉。
  double _target() =>
      AppFontScale.resolveScale(step: widget.step, systemFactor: _system);

  /// 当前正在显示的倍率（动画中按缓动曲线取中间值）。
  double _current() {
    if (!_override) return _target();
    if (!_drive.isAnimating && _drive.value >= 1.0) return _to;
    return _from + (_to - _from) * Curves.easeOutCubic.transform(_drive.value);
  }

  void _retarget() {
    final double? fixed = AppFontScale.scaleOf(widget.step);
    final double target = _target();
    final double current = _current();

    // 回到 0 档且本来就没在覆盖：什么都不用做（原样跟随系统）。
    if (fixed == null && !_override) return;

    // 目标与当前几乎一致（例如在两个 1.0 之间来回）：直接落位。
    if ((current - target).abs() < 0.0005) {
      setState(() {
        _from = _to = target;
        _override = fixed != null;
      });
      _drive.value = 1.0;
      return;
    }

    // 减少动态效果：一帧到位。
    if (_reduceMotion) {
      setState(() {
        _from = _to = target;
        _override = fixed != null;
      });
      _drive.value = 1.0;
      return;
    }

    setState(() {
      _from = current;
      _to = target;
      _override = true;
    });
    _drive.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      // 落到 0 档：动画结束后撤掉覆盖，把系统字号原样交还。
      if (AppFontScale.scaleOf(widget.step) == null) {
        setState(() => _override = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_override) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _drive,
      // child 传进来 ⇒ 每一帧只重建 MediaQuery 这一层，不重建整棵树的内容。
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_current())),
          child: child!,
        );
      },
    );
  }
}
