import 'package:flutter/material.dart';

import '../pages/group_home_page.dart';
import '../pages/home_page.dart';
import '../pages/my_home_page.dart';
import '../pages/world_page.dart';
import '../state/app_controller.dart';
import 'app_drawer.dart';

Widget _buildSectionPage(AppSection target, AppController controller) {
  switch (target) {
    case AppSection.home:
      return HomePage(controller: controller);
    case AppSection.groupChats:
      return GroupHomePage(controller: controller);
    case AppSection.myHome:
      return MyHomePage(controller: controller);
    case AppSection.world:
      return WorldPage(controller: controller);
    case AppSection.settings:
      return HomePage(controller: controller);
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
      selectedIndex: current.index,
      onDestinationSelected: (int index) {
        navigateToSection(
          context,
          controller,
          AppSection.values[index],
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
