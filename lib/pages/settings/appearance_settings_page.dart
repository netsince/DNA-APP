// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'appearance_app_page.dart';
import 'appearance_chat_page.dart';
import 'appearance_theme_page.dart';

/// 外观与体验：分类入口页。
///
/// 按「主题与颜色 / 应用与启动 / 聊天界面」分组。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('外观与体验')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          _EntryTile(
            icon: Icons.palette_outlined,
            title: '主题与颜色',
            subtitle: '亮暗模式切换与自动提取/自定义强调色方案',
            onTap: () => _push(context, AppearanceThemePage(controller: controller)),
          ),
          const SizedBox(height: 10),
          _EntryTile(
            icon: Icons.apps_outlined,
            title: '应用与启动',
            subtitle: '桌面应用图标、开场动画与聊天记忆容量仪表盘',
            onTap: () => _push(context, AppearanceAppPage(controller: controller)),
          ),
          const SizedBox(height: 10),
          _EntryTile(
            icon: Icons.chat_bubble_outline,
            title: '聊天界面',
            subtitle: '气泡透明度、背景遮罩暗度、半屏模式与快捷按钮',
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
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
        ),
        title: FitText(title, style: ts.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: FitText(subtitle, style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
