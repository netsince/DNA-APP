import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'liquid_glass.dart';

/// 全局画布：给所有页面垫一层深色渐变底。
///
/// 玻璃质感靠「背景有层次 + 前景半透明」才成立，纯平滑底会让卡片看起来
/// 像灰色方块。这里用三段渐变（左上偏亮、右下偏深）制造柔和的光照方向。
///
/// 深色配色由 [AppSurfaces] 派生，用户在「界面配色」里换底色时这里一起变。
/// 只用 `DecoratedBox`，**不产生任何模糊/离屏合成**，滚动静止时零开销。
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color top = Color.lerp(AppSurfaces.canvasDark, Colors.white, 0.02)!;
    final Color bottom = Color.lerp(AppSurfaces.canvasDark, Colors.black, 0.25)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? <Color>[top, AppSurfaces.canvasDark, bottom]
              : const <Color>[
                  Color(0xFFF8FAFD),
                  Color(0xFFEDF1F7),
                ],
          stops: dark ? const <double>[0.0, 0.55, 1.0] : null,
        ),
      ),
      child: child,
    );
  }
}

/// 玻璃面板：半透明填充 + 1px 高光描边 + 可选柔光投影。
///
/// 业务页面需要「一块浮起来的玻璃」时用它，而不是手写
/// `Container(decoration: ...)`——描边/填充/阴影都走设计令牌。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = AppInsets.card,
    this.borderRadius = AppRadius.mdAll,
    this.elevated = false,
    this.blur = false,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// 是否带 [AppShadows.glass] 投影（浮层/主卡片用）。
  final bool elevated;

  /// 是否做背景模糊（**开销大**：整块区域每帧离屏合成，只在固定不动的
  /// 浮层上用，如侧边栏、底部输入栏）。
  final bool blur;

  final bool clip;

  @override
  Widget build(BuildContext context) {
    // 液态玻璃：厚度渐变 + 镜面高光 + 上亮下暗的折射边，见 LiquidGlass。
    return LiquidGlass(
      padding: padding,
      borderRadius: borderRadius,
      blur: blur ? 18 : 0,
      elevated: elevated,
      tint: Theme.of(context).colorScheme.primary,
      child: child,
    );
  }
}
