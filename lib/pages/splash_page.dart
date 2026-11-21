import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'splash/splash_animations.dart';

// 旧的引用点（如果有）仍可从 splash_page.dart 拿到默认动画。
export 'splash/logo_draw_animation.dart' show LogoDrawAnimation;

/// 开场动画的**外壳**：只负责底色与居中，播哪段由 [SplashPage.animation] 决定。
///
/// 动画本身在 `splash/splash_animations.dart` 里声明（数据驱动）：
/// 想加一种新动画，只改那张表，不用碰这个文件和启动逻辑。
class SplashPage extends StatelessWidget {
  const SplashPage({
    super.key,
    required this.animation,
    required this.onComplete,
  });

  final SplashAnimationSpec animation;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      // 用动画 id 当 key：设置里换动画时会重建子树，不会复用上一段动画的
      // State（复用的后果是控制器还停在「已播完」，新动画一帧都不播）。
      body: Center(
        child: KeyedSubtree(
          key: ValueKey<String>(animation.id),
          child: animation.build(context, onComplete, animation.durationMs),
        ),
      ),
    );
  }
}

