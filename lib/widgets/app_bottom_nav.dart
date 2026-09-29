import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'app_section.dart';

/// 底部导航栏实际承载的栏目（主页 / 群聊 / 我家 / 世界）。
/// 注意：AppSection 枚举里 identity(3)、settings(5) 不在底栏中，
/// 因此**不能**用 `AppSection.values[index]` 直接映射 destination 的 index，
/// 否则第 4 个 destination（世界）会错位映射到 identity，且 world 的 index(4)
/// 会超出 destinations 数量导致 selectedIndex 越界崩溃。
const List<AppSection> _bottomSections = <AppSection>[
  AppSection.home,
  AppSection.groupChats,
  AppSection.myHome,
  AppSection.world,
];

/// 在四个主页面之间切换（fade-through 转场,与抽屉导航一致）。
void navigateToSection(
  BuildContext context,
  AppController controller,
  AppSection target, {
  required AppSection current,
}) {
  sectionNavigate(
    context,
    controller,
    target,
    current: current,
  );
}

/// 底部导航栏：主页 / 群聊 / 我家 / 世界。仅在开启「主页底部导航栏」时显示。
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.controller,
    required this.current,
  });

  final AppController controller;
  final AppSection current;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      // 当前栏目不在底栏中（如身份/设置）时返回 -1，表示不选中任何项。
      selectedIndex: _bottomSections.indexOf(current),
      onDestinationSelected: (int index) {
        navigateToSection(
          context,
          controller,
          _bottomSections[index],
          current: current,
        );
      },
      destinations: const <Widget>[
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '主页',
        ),
        NavigationDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: '群聊',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: '我家',
        ),
        NavigationDestination(
          icon: Icon(Icons.public_outlined),
          selectedIcon: Icon(Icons.public),
          label: '世界',
        ),
      ],
    );
  }
}
