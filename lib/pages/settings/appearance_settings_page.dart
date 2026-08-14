import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'appearance_app_page.dart';
import 'appearance_chat_page.dart';
import 'appearance_theme_page.dart';

/// 外观与体验：分类入口页。
///
/// 按「主题与颜色 / 应用与启动 / 聊天界面」分组，
/// 每组一个入口，点击进入对应的设置页，避免把所有设置项平铺在一个页面。
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
          _EntryTile(
            icon: Icons.palette,
            title: '主题与颜色',
            onTap: () => _push(context, AppearanceThemePage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.apps,
            title: '应用与启动',
            onTap: () => _push(context, AppearanceAppPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.chat_bubble,
            title: '聊天界面',
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

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
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
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
