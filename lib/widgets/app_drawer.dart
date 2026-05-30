import 'package:flutter/material.dart';

import '../pages/community_page.dart';
import '../pages/home_page.dart';
import '../pages/group_home_page.dart';
import '../pages/my_home_page.dart';
import '../pages/settings_page.dart';
import '../pages/world_page.dart';
import '../state/app_controller.dart';

enum AppSection { home, groupChats, myHome, world, community, settings }

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.controller, required this.current});

  final AppController controller;
  final AppSection current;

  void _navigate(BuildContext context, AppSection target) {
    if (target == current) {
      Navigator.of(context).pop();
      return;
    }
    final Widget page;
    switch (target) {
      case AppSection.home:
        page = HomePage(controller: controller);
        break;
      case AppSection.groupChats:
        page = GroupHomePage(controller: controller);
        break;
      case AppSection.myHome:
        page = MyHomePage(controller: controller);
        break;
      case AppSection.world:
        page = WorldPage(controller: controller);
        break;
      case AppSection.community:
        page = CommunityPage(controller: controller);
        break;
      case AppSection.settings:
        page = SettingsPage(controller: controller);
        break;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Duet Nurturing Ally', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('与汝共奏', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('首页'),
            selected: current == AppSection.home,
            onTap: () => _navigate(context, AppSection.home),
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('群聊'),
            selected: current == AppSection.groupChats,
            onTap: () => _navigate(context, AppSection.groupChats),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('我家'),
            selected: current == AppSection.myHome,
            onTap: () => _navigate(context, AppSection.myHome),
          ),
          ListTile(
            leading: const Icon(Icons.public_outlined),
            title: const Text('世界'),
            selected: current == AppSection.world,
            onTap: () => _navigate(context, AppSection.world),
          ),
          ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: const Text('社区'),
            selected: current == AppSection.community,
            onTap: () => _navigate(context, AppSection.community),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            selected: current == AppSection.settings,
            onTap: () => _navigate(context, AppSection.settings),
          ),
        ],
      ),
    );
  }
}
