import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'app_section.dart';

/// 底部导航栏承载的全部栏目（主页 / 群聊 / 我家 / 世界 / 社区）。
///
/// 注意：AppSection 枚举里 identity、settings 不在底栏中，
/// 因此**不能**用 AppSection.values[index] 直接映射 destination 的 index，
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

/// 一个导航目的地的图标与文案。
///
/// **底栏（NavigationBar）与侧栏（NavigationRail）共用这一份**：
/// 同一个目的地在不同断点下文案与图标必须一致，各写一套迟早会漂移。
class AppNavMeta {
  const AppNavMeta({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 底部导航栏：主页 / 群聊 / 我家 / 世界（+ 社区）。
///
/// 只在 compact 宽度（小于 600）下出现；中等及以上由 [AppSectionShell]
/// 换成 NavigationRail（见 docs/MATERIAL_DESIGN_AUDIT.md 3.4）。
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

  /// 侧栏在当前设置下实际承载的栏目（与底栏同一集合）。
  static List<AppSection> sectionsFor(AppController controller) =>
      controller.settings.enableCommunity
      ? _allSections
      : _allSections
            .where((AppSection s) => s != AppSection.community)
            .toList(growable: false);

  /// [current] 是否出现在底栏里。
  ///
  /// **身份 / 设置不在底栏中**（只从抽屉或侧栏进入），而 NavigationBar
  /// 与 NavigationRail 的 selectedIndex 必须落在区间内 —— NavigationBar 不
  /// 接受 -1 表示「无选中项」，传进去会直接断言崩溃。所以这种栏目下根本不要
  /// 渲染底栏：由 AppSectionShellState.build 把关。
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

  /// 目的地元数据（图标 / 选中图标 / 文案）。
  static AppNavMeta metaFor(AppSection section) => switch (section) {
    AppSection.home => const AppNavMeta(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: '主页',
    ),
    AppSection.groupChats => const AppNavMeta(
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
      label: '群聊',
    ),
    AppSection.myHome => const AppNavMeta(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: '我家',
    ),
    AppSection.world => const AppNavMeta(
      icon: Icons.public_outlined,
      selectedIcon: Icons.public,
      label: '世界',
    ),
    AppSection.community => const AppNavMeta(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      label: '社区',
    ),
    // 身份 / 设置不在底栏与侧栏里；真被传进来时给个中性图标兜底。
    AppSection.identity => const AppNavMeta(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: '身份',
    ),
    AppSection.settings => const AppNavMeta(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '设置',
    ),
  };

  /// 侧栏用的目的地（M3 NavigationRail）。
  static NavigationRailDestination railDestination(AppSection section) {
    final AppNavMeta meta = metaFor(section);
    return NavigationRailDestination(
      icon: Icon(meta.icon),
      selectedIcon: Icon(meta.selectedIcon),
      label: Text(meta.label),
    );
  }

  static NavigationDestination _destination(AppSection section) {
    final AppNavMeta meta = metaFor(section);
    return NavigationDestination(
      icon: Icon(meta.icon),
      selectedIcon: Icon(meta.selectedIcon),
      label: meta.label,
    );
  }
}
