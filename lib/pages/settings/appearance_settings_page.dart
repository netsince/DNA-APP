import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'appearance_app_page.dart';
import 'appearance_chat_page.dart';
import 'appearance_theme_page.dart';

/// 外观与体验：分类入口页。
///
/// 按「主题与颜色 / 应用与启动 / 聊天界面」分组，
/// 点击列表项进入对应的设置页，避免把所有设置项平铺在一个页面。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('外观与体验')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _GroupHeader(icon: Icons.palette, title: '主题与颜色',
              subtitle: '应用主题模式与强调色'),
          _EntryTile(
            icon: Icons.brightness_6,
            title: '主题模式',
            subtitle: '跟随系统 / 亮色 / 暗色',
            onTap: () => _push(context, AppearanceThemePage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.color_lens,
            title: '强调色',
            subtitle: '自动 / 自定义颜色',
            onTap: () => _push(context, AppearanceThemePage(controller: controller)),
          ),
          _GroupHeader(icon: Icons.apps, title: '应用与启动',
              subtitle: '应用图标、启动动画与导航显示'),
          _EntryTile(
            icon: Icons.widgets,
            title: '应用图标',
            subtitle: '更换启动器 / 浏览器标签页图标',
            onTap: () => _push(context, AppearanceAppPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.rocket_launch,
            title: '启动与导航',
            subtitle: '开场动画、主页底部导航栏、Token 仪表盘、重新进入 OOBE',
            onTap: () => _push(context, AppearanceAppPage(controller: controller)),
          ),
          _GroupHeader(icon: Icons.chat_bubble, title: '聊天界面',
              subtitle: '聊天相关的显示细节'),
          _EntryTile(
            icon: Icons.dashboard_customize,
            title: '背景与气泡',
            subtitle: '遮罩强度、气泡透明度、半屏聊天',
            onTap: () => _push(context, AppearanceChatPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.bolt,
            title: '消息快捷按钮与提示时长',
            subtitle: '气泡快捷按钮、底部提示显示时长',
            onTap: () => _push(context, AppearanceChatPage(controller: controller)),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FitText(title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
                const SizedBox(height: 2),
                FitText(subtitle,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: FitText(title),
        subtitle: FitText(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
