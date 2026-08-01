import 'package:flutter/material.dart';

import '../pages/group_home_page.dart';
import '../pages/home_page.dart';
import '../pages/identity_page.dart';
import '../pages/my_home_page.dart';
import '../pages/settings_page.dart';
import '../pages/world_page.dart';
import '../state/app_controller.dart';
import 'app_drawer.dart';

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

Widget _buildSectionPage(AppSection target, AppController controller) {
  switch (target) {
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

/// 在四个主页面之间切换（与抽屉导航行为一致，使用 pushReplacement）。
void navigateToSection(
  BuildContext context,
  AppController controller,
  AppSection target, {
  required AppSection current,
}) {
  if (target == current) {
    return;
  }
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => _buildSectionPage(target, controller),
    ),
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
