import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

/// 沉浸态的**唯一常驻控件**：右上角「退出沉浸」。
///
/// 从 `chat_surface` 的 build 里搬出来的。原来它是从无到有地蹦出来，后来改成
/// 缩放 + 淡入（进出沉浸时不再闪一下）；这一套动画与显隐条件现在跟组件在一起，
/// 而不是散在 480 行的 build 中间。
///
/// 显隐靠 `visible` 控制：不可见时用 [IgnorePointer] 挡住点击 —— 否则用户会在
/// 看不见的地方点到一个「退出沉浸」。
class ImmersiveExitButton extends StatelessWidget {
  const ImmersiveExitButton({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedScale(
          scale: visible ? 1.0 : 0.8,
          duration: AppMotion.fast,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: AppMotion.fast,
            curve: Curves.easeOutCubic,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: IconButton.filledTonal(
                  onPressed: onPressed,
                  tooltip: '退出沉浸',
                  icon: const Icon(Icons.fullscreen_exit),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
