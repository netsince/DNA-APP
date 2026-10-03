import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'app_section.dart';

/// 底部导航栏承载的全部栏目（主页 / 群聊 / 我家 / 世界 / 社区）。
/// 注意：AppSection 枚举里 identity、settings 不在底栏中，
/// 因此**不能**用 `AppSection.values[index]` 直接映射 destination 的 index，
/// 否则底栏第 4 格（世界）会错位映射到 identity，且 world 的枚举下标
/// 会超出 destinations 数量，导致 selectedIndex 越界崩溃。
/// （越界这件事现在由 [showsFor] 从源头挡住，见下。）
const List<AppSection> _allSections = <AppSection>[
  AppSection.home,
  AppSection.groupChats,
  AppSection.myHome,
  AppSection.world,
  AppSection.community,
];

/// 底部导航栏：主页 / 群聊 / 我家 / 世界（+ 社区）。仅在开启「底部导航栏」时显示。
///
/// 位置固定在栏目壳上,不随切换滑动;点击后由壳在内容区滑胶片
/// (横向:按底栏顺序滑,群聊 → 世界会掠过我家;与抽屉共用一套令牌)。
///
/// 「社区」可以在设置里关掉：关掉后这一格直接从底栏消失（见 [enableCommunity]）。
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.controller,
    required this.current,
  });

  final AppController controller;
  final AppSection current;

  /// 是否显示「社区」入口。
  bool get enableCommunity => controller.settings.enableCommunity;

  /// 本次实际渲染的栏目列表（关掉社区时摘掉社区）。
  List<AppSection> get _sections => sectionsFor(controller);

  /// 底栏在当前设置下实际承载的栏目。
  static List<AppSection> sectionsFor(AppController controller) =>
      controller.settings.enableCommunity
          ? _allSections
          : _allSections
              .where((AppSection s) => s != AppSection.community)
              .toList(growable: false);

  /// [current] 是否出现在底栏里。
  ///
  /// **身份 / 设置不在底栏中**（它们只从抽屉进），而 [NavigationBar] 的
  /// `selectedIndex` 必须落在 `[0, destinations.length)` —— 它**不接受 -1
  /// 表示「无选中项」**，传进去会直接断言崩溃、掀掉整棵树。所以这种栏目
  /// 下**根本不要渲染底栏**：由 [AppSectionShellState.build] 用本方法把关。
  static bool showsFor(AppController controller, AppSection current) =>
      sectionsFor(controller).contains(current);

  @override
  Widget build(BuildContext context) {
    final List<AppSection> sections = _sections;
    // 兜底：即使有人绕过 [showsFor] 直接构造，也不能把越界下标交给
    // NavigationBar（它一崩就是整棵树）。
    final int rawIndex = sections.indexOf(current);
    final int selectedIndex = rawIndex < 0 ? 0 : rawIndex;
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (int index) {
        AppSectionShell.maybeOf(
          context,
        )?.navigateTo(sections[index], axis: Axis.horizontal);
      },
      destinations: <Widget>[
        for (final AppSection s in sections) _destination(s),
      ],
    );
  }

  static NavigationDestination _destination(AppSection section) =>
      switch (section) {
        AppSection.home => const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '主页',
          ),
        AppSection.groupChats => const NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: '群聊',
          ),
        AppSection.myHome => const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: '我家',
          ),
        AppSection.world => const NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: '世界',
          ),
        AppSection.community => const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '社区',
          ),
        // 身份/设置不在底栏中；真被传进来时给个中性图标兜底。
        AppSection.identity => const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '身份',
          ),
        AppSection.settings => const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
      };
}
