import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../pages/search_page.dart';
import '../state/app_controller.dart';
import 'app_container.dart';
import 'app_section.dart';
import 'drawer_cover.dart';
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
          // 封面：星野 + 光晕 + LOGO + 英文小标与「与汝共奏」。
          // 星点与光晕都是绘制出来的，跟着界面配色变色，不含位图。
          const RepaintBoundary(child: DrawerCover()),
          // 搜索是独立界面(不是栏目):从侧边栏这一行**容器变换**
          // 长出搜索页,关闭时缩回原位——与卡片、右上角按钮同一族
          // 动效。抽屉模式下先收抽屉再起飞(两段动画同帧并行)。
          AppContainer<bool>(
            // 点击由 ListTile 自己发起(保留水波纹),容器不抢手势。
            tappable: false,
            closedBuilder: (BuildContext context, VoidCallback open) =>
                _glassShell(
                  selected: false,
                  child: ListTile(
                    leading: Icon(
                      Icons.search_outlined,
                      color: AppSurfaces.inkSecondary,
                    ),
                    title: FitText(
                      '搜索',
                      style: TextStyle(color: AppSurfaces.inkSecondary),
                    ),
                    onTap: () {
                      if (!persistent) Navigator.of(context).pop();
                      open();
                    },
                  ),
                ),
            openBuilder: (BuildContext context, VoidCallback close) =>
                SearchPage(controller: controller),
          ),
          _navTile(
            icon: Icons.home_outlined,
            label: '首页',
            selected: current == AppSection.home,
            onTap: () => _navigate(context, AppSection.home),
          ),
          _navTile(
            icon: Icons.forum_outlined,
            label: '群聊',
            selected: current == AppSection.groupChats,
            onTap: () => _navigate(context, AppSection.groupChats),
          ),
          _navTile(
            icon: Icons.people_outline,
            label: '我家',
            selected: current == AppSection.myHome,
            onTap: () => _navigate(context, AppSection.myHome),
          ),
          // 顺序 = AppSection 枚举顺序（也是纵向滑动的胶片顺序）：
          // 身份排在「世界」下面。
          _navTile(
            icon: Icons.public_outlined,
            label: '世界',
            selected: current == AppSection.world,
            onTap: () => _navigate(context, AppSection.world),
          ),
          _navTile(
            icon: Icons.person_outline,
            label: '身份',
            selected: current == AppSection.identity,
            onTap: () => _navigate(context, AppSection.identity),
          ),
          // 「社区」可在设置里整体关掉：关掉后侧边栏（含横屏常驻侧栏）里
          // 不再出现这一行，也不做任何预热。
          if (controller.settings.enableCommunity)
            _navTile(
              icon: Icons.explore_outlined,
              label: '社区',
              selected: current == AppSection.community,
              onTap: () => _navigate(context, AppSection.community),
            ),
          _navTile(
            icon: Icons.settings_outlined,
            label: '设置',
            selected: current == AppSection.settings,
            onTap: () => _navigate(context, AppSection.settings),
          ),
        ],
      ),
    );
  }

  /// 玻璃胶囊外壳：导航项统一套一层半透明玻璃，选中态更实、描边更亮。
  Widget _glassShell({required bool selected, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? AppSurfaces.glassFillStrong
              : AppSurfaces.glassFillWeak,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected
                ? AppSurfaces.glassBorder
                : AppSurfaces.glassBorderSoft,
          ),
        ),
        child: child,
      ),
    );
  }

  /// 侧边栏导航项。
  Widget _navTile({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final Color ink =
        selected ? AppSurfaces.inkPrimary : AppSurfaces.inkSecondary;
    return _glassShell(
      selected: selected,
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        selected: selected,
        selectedTileColor: Colors.transparent,
        leading: Icon(icon, color: ink),
        title: FitText(
          label,
          style: TextStyle(
            color: ink,
            fontWeight: selected ? AppWeight.medium : AppWeight.regular,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
