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
///
/// 枚举顺序即**抽屉自上而下**的顺序,也是纵向滑动的"胶片"顺序:
/// 从首页滑到世界,会依次经过群聊、我家、身份。
enum AppSection { home, groupChats, myHome, identity, world, settings }

/// 底栏(横向)的滑动顺序:前四项与底栏一致;身份/设置不在底栏中,
/// 追加在末尾——仅当从它们出发横向切换时才会作为端点或途经页。
const List<AppSection> kHorizontalSectionOrder = <AppSection>[
  AppSection.home,
  AppSection.groupChats,
  AppSection.myHome,
  AppSection.world,
  AppSection.identity,
  AppSection.settings,
];

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

/// 滑行时长随距离递增:首步 [AppMotion.sectionTravel],
/// 每多经过一个栏目加 [AppMotion.sectionTravelStep],
/// 封顶 [AppMotion.sectionTravelCap]。
Duration sectionTravelDuration(int distance) {
  if (distance <= 1) {
    return AppMotion.sectionTravel;
  }
  final int ms = AppMotion.sectionTravel.inMilliseconds +
      (distance - 1) * AppMotion.sectionTravelStep.inMilliseconds;
  if (ms > AppMotion.sectionTravelCap.inMilliseconds) {
    return AppMotion.sectionTravelCap;
  }
  return Duration(milliseconds: ms);
}

/// 栏目切换的统一入口:滑动胶片路由替换当前页。
///
/// * 抽屉(纵向):按 [AppSection] 枚举顺序滑,首页 → 世界会依次
///   掠过群聊、我家、身份;
/// * 底栏(横向,传 [Axis.horizontal]):按 [kHorizontalSectionOrder]
///   滑,群聊 → 世界掠过我家。
///
/// 调用方如需同时收起抽屉,**先** `Navigator.pop`(抽屉开始滑出)
/// **再**调本函数——两段动画同帧启动、自然并行。
void sectionNavigate(
  BuildContext context,
  AppController controller,
  AppSection target, {
  required AppSection current,
  Axis axis = Axis.vertical,
}) {
  if (target == current) {
    return;
  }
  Navigator.of(context).pushReplacement(
    AppSectionSwitcher(
      controller: controller,
      target: target,
      current: current,
      axis: axis,
    ),
  );
}

/// 栏目切换的"滑动胶片"转场路由。
///
/// ## 概念
///
/// 把栏目想成一条首尾相接的胶片:切换 = 胶片从当前栏目滑到目标栏目,
/// **中间栏目真的从视口里掠过**(不是凭空淡换)。
/// 纵向(抽屉)按抽屉顺序滑,横向(底栏)按底栏顺序滑。
///
/// ## 实现
///
/// 一条不透明路由盖在当前页上,内部是一个逐帧平移的层叠:
/// 每个栏目的偏移 = `(k - from) - t × (to - from)` 个视口
/// (t 为缓动后的进度)。途经页**接近视口(±1 步)才挂载**、
/// 离开即卸载——任意时刻最多两三页在场,构造成本摊到整段飞行,
/// 远端页面不会一次性 build;各页 widget 实例全程不变,
/// 只重算位置,页面状态在滑行中不重建。
/// t=1 时仅剩目标页常驻(Positioned 带 ValueKey,按 key 收敛,
/// 目标页元素不重建)。
///
/// 时长随距离递增(见 [sectionTravelDuration]),
/// 曲线 [AppMotion.travel]:快出缓收,掠过的栏目可辨又不拖沓。
class AppSectionSwitcher extends PageRouteBuilder<void> {
  /// 参见工厂构造;私有构造承接预计算结果。
  AppSectionSwitcher._({
    required Axis axis,
    required int fromIndex,
    required int toIndex,
    required Duration duration,
    required List<AppSection> sections,
    required List<Widget> pages,
  }) : super(
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          opaque: true,
          maintainState: false,
          pageBuilder: (BuildContext context, Animation<double> _,
                  Animation<double> secondary) =>
              pages[toIndex],
          transitionsBuilder:
              (BuildContext context, Animation<double> animation,
                      Animation<double> secondary, Widget child) =>
                  buildFlight(
            context: context,
            animation: animation,
            axis: axis,
            fromIndex: fromIndex,
            toIndex: toIndex,
            sections: sections,
            pages: pages,
            child: child,
          ),
        );

  /// 参见 [sectionNavigate]。
  factory AppSectionSwitcher({
    required AppController controller,
    required AppSection target,
    required AppSection current,
    Axis axis = Axis.vertical,
  }) {
    final List<AppSection> sections =
        axis == Axis.vertical ? AppSection.values : kHorizontalSectionOrder;
    final int fromIndex = sections.indexOf(current);
    final int toIndex = sections.indexOf(target);
    assert(fromIndex >= 0 && toIndex >= 0, '栏目不在对应轴的顺序表里');
    // widget 构造很轻(仅配置对象),全部预建;
    // 真正的挂载(build/layout)由 buildFlight 按 ±1 步窗口惰性进行。
    final List<Widget> pages = <Widget>[
      for (final AppSection s in sections) sectionPage(s, controller),
    ];
    return AppSectionSwitcher._(
      axis: axis,
      fromIndex: fromIndex,
      toIndex: toIndex,
      duration: sectionTravelDuration((toIndex - fromIndex).abs()),
      sections: sections,
      pages: pages,
    );
  }

  /// 胶片飞行:逐帧计算各栏目的偏移并按可见窗口挂载。
  ///
  /// 公开为 static:纯函数(输入进度/顺序/页面),可被测试
  /// 与其他路由直接复用。`pages` 与 `sections` 一一对应,
  /// `child` 必须与 `pages[toIndex]` 同一实例。
  static Widget buildFlight({
    required BuildContext context,
    required Animation<double> animation,
    required Axis axis,
    required int fromIndex,
    required int toIndex,
    required List<AppSection> sections,
    required List<Widget> pages,
    required Widget child,
  }) {
    final Animation<double> eased =
        CurvedAnimation(parent: animation, curve: AppMotion.travel);
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? _) {
        final double t = eased.value;
        final Size vp = MediaQuery.of(context).size;
        final List<Widget> layers = <Widget>[];
        for (int k = 0; k < pages.length; k++) {
          // 页面左/上边缘的位置(单位:视口)。t=1 时目标页归 0。
          final double step = (k - fromIndex) - t * (toIndex - fromIndex);
          // 可见窗口(-1, 1):仅覆盖或即将覆盖视口的页面在场,
          // 途经页惰性挂载、离开即卸。t=1 时旧页恰好在 ±1 处被卸下。
          if (step <= -1 || step >= 1) {
            continue;
          }
          layers.add(
            Positioned(
              key: ValueKey<AppSection>(sections[k]),
              left: axis == Axis.horizontal ? step * vp.width : 0,
              top: axis == Axis.vertical ? step * vp.height : 0,
              width: vp.width,
              height: vp.height,
              child: pages[k],
            ),
          );
        }
        return Stack(clipBehavior: Clip.hardEdge, children: layers);
      },
    );
  }
}
