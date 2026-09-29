import 'package:flutter/material.dart';

import '../pages/search_page.dart';
import '../state/app_controller.dart';
import 'app_section.dart';
import 'package:dna/widgets/fit_text.dart';

export 'app_section.dart' show AppSection;

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.controller,
    required this.current,
    this.persistent = false,
  });

  final AppController controller;
  final AppSection current;

  /// 常驻模式：横屏时侧边栏固定显示，不弹抽屉，因此点击导航项不执行 pop。
  final bool persistent;

  void _navigate(BuildContext context, AppSection target) {
    // 同栏目:仅收抽屉,不切换。
    if (target == current) {
      if (!persistent) Navigator.of(context).pop();
      return;
    }
    // 栏目切换 = 滑动胶片(纵向,按抽屉自上而下的顺序):
    // 首页 → 世界会依次掠过群聊、我家、身份。
    // 先 pop(抽屉开始滑出),紧接着 push(胶片起飞):
    // 同一帧启动并行播放。顺序不能反:pop 弹的是页面路由上的
    // 抽屉 LocalHistory,若先 push,pop 会命中新路由。
    if (!persistent) Navigator.of(context).pop();
    sectionNavigate(context, controller, target, current: current);
  }

  @override
  Widget build(BuildContext context) {
    // 常驻模式：直接返回内容（不带 Drawer 的半透明遮罩 / 滑入动画），
    // 由外层（[AppScaffold]）把它作为固定侧边栏嵌入布局。
    if (persistent) {
      return buildContent(context);
    }
    return Drawer(child: buildContent(context));
  }

  /// 侧边栏内容。常驻模式下由外层（[AppScaffold]）直接嵌入布局。
  Widget buildContent(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration:
                BoxDecoration(color: theme.colorScheme.primaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FitText('Duet Nurturing Ally',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                FitText('与汝共奏', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.search_outlined),
            title: const FitText('搜索'),
            onTap: () {
              if (!persistent) Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      SearchPage(controller: controller),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const FitText('首页'),
            selected: current == AppSection.home,
            onTap: () => _navigate(context, AppSection.home),
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const FitText('群聊'),
            selected: current == AppSection.groupChats,
            onTap: () => _navigate(context, AppSection.groupChats),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const FitText('我家'),
            selected: current == AppSection.myHome,
            onTap: () => _navigate(context, AppSection.myHome),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const FitText('身份'),
            selected: current == AppSection.identity,
            onTap: () => _navigate(context, AppSection.identity),
          ),
          ListTile(
            leading: const Icon(Icons.public_outlined),
            title: const FitText('世界'),
            selected: current == AppSection.world,
            onTap: () => _navigate(context, AppSection.world),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const FitText('设置'),
            selected: current == AppSection.settings,
            onTap: () => _navigate(context, AppSection.settings),
          ),
        ],
      ),
    );
  }
}

/// 自适应脚手架：竖屏时使用抽屉导航；横屏时侧边栏常驻显示。
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.controller,
    required this.current,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawerWidth = 260,
  });

  final AppController controller;
  final AppSection current;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  /// 横屏常驻侧边栏宽度。
  final double drawerWidth;

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (landscape) {
      // 横屏：左侧常驻侧边栏，右侧内容区（含 AppBar）。
      final Widget drawer = AppDrawer(
        controller: controller,
        current: current,
        persistent: true,
      );
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: drawerWidth,
              child: drawer,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ?appBar,
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }

    // 竖屏：抽屉式导航。
    return Scaffold(
      appBar: appBar,
      drawer: AppDrawer(controller: controller, current: current),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
