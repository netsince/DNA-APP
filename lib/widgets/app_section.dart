import 'package:flutter/material.dart';

import 'package:dna/pages/group_home_page.dart';
import 'package:dna/pages/home_page.dart';
import 'package:dna/pages/identity_page.dart';
import 'package:dna/pages/my_home_page.dart';
import 'package:dna/pages/settings_page.dart';
import 'package:dna/pages/world_page.dart';
import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';

/// 主导航的栏目:抽屉与底部导航栏共用这一份定义。
enum AppSection { home, groupChats, myHome, identity, world, settings }

/// 栏目 → 页面实例。
Widget sectionPage(AppSection section, AppController controller) {
  switch (section) {
    case AppSection.home:
      return HomePage(controller: controller);
    case AppSection.groupChats:
      return GroupHomePage(controller: controller);
    case AppSection.myHome:
      return MyHomePage(controller: controller);
    case AppSection.identity:
      return IdentityPage(controller: controller);
    case AppSection.world:
      return WorldPage(controller: controller);
    case AppSection.settings:
      return SettingsPage(controller: controller);
  }
}

/// 栏目切换的统一入口:一条 fade-through 路由替换当前页。
///
/// 调用方如需同时收起抽屉,**先** `Navigator.pop`(抽屉开始滑出)
/// **再**调本函数 —— 两段动画同帧启动、自然并行。
void sectionNavigate(
  BuildContext context,
  AppController controller,
  AppSection target, {
  required AppSection current,
}) {
  if (target == current) {
    return;
  }
  Navigator.of(context).pushReplacement(
    AppSectionSwitcher(controller: controller, target: target),
  );
}

/// 栏目切换的统一转场:fade-through(旧页淡出 → 新页从 90% 缩放浮起)。
///
/// ## 为什么不是左右横推
///
/// 抽屉 / 底栏切换的是**平级栏目**,不是深入一层;
/// `MaterialPageRoute` 的横推自带"层级深入"的方向语义,与操作意图相反,
/// 且 push 动画结束时旧页原地消失,能看见一道"换页的缝"。
/// fade-through 没有方向感 —— 正是 Material 3 为顶级目的地之间
/// 切换定义的官方动效:旧页淡出、新页浮起,没有缝。
///
/// ## 实现方式
///
/// 一条不透明路由盖在当前页上:
/// * 0 ~ 0.35:纯背景色信封,不透明度随进度变化。因为旧页在路由下方
///   且自身保持原状,信封不透明时视觉上就是"旧页淡出",
///   信封透明度回落时露出的是新页 —— 中间没有内容闪烁;
/// * 0.35 ~ 1.0:新页以 fade-through 缓动淡入并从 90% 缩放到 100%。
///
/// 转场节奏(时长/分界/曲线)全部来自 [AppMotion] 的 section 令牌,
/// 16 处容器变换与这里是同一套动效系统。
///
/// 抽屉场景的编排(见 [AppDrawer._navigate]):
/// 先压入本路由、拿到回调后立即关闭抽屉 —— 抽屉滑走与新页浮起
/// 同时进行,不再"先收抽屉、再整页横推"两段等待。
class AppSectionSwitcher extends PageRouteBuilder<void> {
  AppSectionSwitcher({
    required AppController controller,
    required this.target,
  }) : super(
          transitionDuration: AppMotion.section,
          reverseTransitionDuration: AppMotion.section,
          opaque: true,
          maintainState: false,
          pageBuilder: (BuildContext context, Animation<double> _,
                  Animation<double> secondary) =>
              sectionPage(target, controller),
          transitionsBuilder: fadeThroughBuilder,
        );

  /// 目标栏目(供返回键语义与测试使用)。
  final AppSection target;

  /// fade-through 三阶段:信封淡入盖住旧页 → 新页淡入浮起。
  /// 路由不透明,信封底色 = surface,与两个栏目页背景一致。
  ///
  /// 公开为 static:转场与页面构建解耦,可被测试/其他路由直接复用。
  static Widget fadeThroughBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> _,
    Widget child,
  ) {
    final Color surface = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? page) {
        final double t = animation.value;
        if (t < AppMotion.fadeInStart) {
          // 阶段一(0 ~ 0.35):背景色信封盖住旧页。
          // 信封不透明度 0→1→回落,由淡出曲线驱动;
          // 恰好在 t=fadeInStart 时信封重新完全透明,露出新页。
          final double cover = 1.0 - CurvedAnimation(
            parent: animation,
            curve: Interval(0, AppMotion.fadeInStart,
                curve: AppMotion.fadeThrough),
          ).value;
          return ColoredBox(
            color: surface.withValues(alpha: cover.clamp(0.0, 1.0)),
            child: const SizedBox.expand(),
          );
        }
        // 阶段二(0.35 ~ 1.0):新页淡入 + 从 90% 浮起到 100%。
        final Animation<double> eased = CurvedAnimation(
          parent: animation,
          curve: Interval(
            AppMotion.fadeInStart,
            1,
            curve: AppMotion.standard,
          ),
        );
        return FadeTransition(
          opacity: eased,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1).animate(eased),
            child: page,
          ),
        );
      },
      child: child,
    );
  }
}
