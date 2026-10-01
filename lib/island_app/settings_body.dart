import 'package:flutter/material.dart';

/// 设置入口列表，无脚手架，由 [RootShell] 承载。
/// 点击条目通过回调把详情页压入外壳栈，从而保持常驻侧边栏/底栏。
/// 样式参考 DNA client 的 SettingsPage（居中、最大宽度约束、带副标题的菜单项）。
class SettingsBody extends StatelessWidget {
  const SettingsBody({
    super.key,
    required this.onOpenServer,
    required this.onOpenAppearance,
    required this.onOpenSponsor,
    required this.onOpenAbout,
  });

  final VoidCallback onOpenServer;
  final VoidCallback onOpenAppearance;
  final VoidCallback onOpenSponsor;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w =
            constraints.maxWidth > 720 ? 720 : constraints.maxWidth;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: <Widget>[
                _MenuItem(
                  icon: Icons.cloud,
                  title: '服务器',
                  subtitle: '后端地址',
                  onTap: onOpenServer,
                ),
                _MenuItem(
                  icon: Icons.palette_outlined,
                  title: '外观',
                  subtitle: '主题、强调色与导航',
                  onTap: onOpenAppearance,
                ),
                _MenuItem(
                  icon: Icons.volunteer_activism_outlined,
                  title: '赞助',
                  subtitle: '支持我们，让这个小岛持续运转',
                  onTap: onOpenSponsor,
                ),
                _MenuItem(
                  icon: Icons.info_outline,
                  title: '关于',
                  subtitle: '应用信息与开源协议',
                  onTap: onOpenAbout,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 设置菜单项：图标 + 标题 + 副标题 + 右箭头，对齐 DNA client 的 _MenuItem。
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
