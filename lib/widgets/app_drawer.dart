import 'package:flutter/material.dart';

import '../pages/search_page.dart';
import '../state/app_controller.dart';
import 'app_container.dart';
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
    // 栏目切换交给栏目壳:抽屉(纵向,按自上而下顺序)滑胶片,
    // 首页 → 世界会依次掠过群聊、我家、身份。框架(侧边栏/标题栏/
    // 底栏)固定在壳上不动,只有内容区在滑。
    // 先记下壳,再收抽屉(两段动画同帧并行);常驻模式无需收。
    final AppSectionShellState? shell = AppSectionShell.maybeOf(context);
    if (!persistent) Navigator.of(context).pop();
    shell?.navigateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    // 常驻模式：直接返回内容（不带 Drawer 的半透明遮罩 / 滑入动画），
    // 由栏目壳（[AppSectionShell]）把它作为固定侧边栏嵌入布局。
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
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FitText(
                  'Duet Nurturing Ally',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                FitText('与汝共奏', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // 搜索是独立界面(不是栏目):从侧边栏这一行**容器变换**
          // 长出搜索页,关闭时缩回原位——与卡片、右上角按钮同一族
          // 动效。抽屉模式下先收抽屉再起飞(两段动画同帧并行)。
          AppContainer<bool>(
            // 点击由 ListTile 自己发起(保留水波纹),容器不抢手势。
            tappable: false,
            closedBuilder: (BuildContext context, VoidCallback open) =>
                ListTile(
                  leading: const Icon(Icons.search_outlined),
                  title: const FitText('搜索'),
                  onTap: () {
                    if (!persistent) Navigator.of(context).pop();
                    open();
                  },
                ),
            openBuilder: (BuildContext context, VoidCallback close) =>
                SearchPage(controller: controller),
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
