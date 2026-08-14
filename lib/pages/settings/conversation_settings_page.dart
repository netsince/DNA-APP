import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'conversation_advanced_page.dart';
import 'conversation_prompt_strategy_page.dart';
import 'conversation_send_page.dart';
import 'conversation_summary_page.dart';

/// 对话与策略：分类入口页。
///
/// 按「提示词策略 / 摘要与上下文 / 回复与发送 / 消息与高级」分组，
/// 点击列表项进入对应的设置页，避免把所有设置项平铺在一个页面。
class ConversationSettingsPage extends StatelessWidget {
  const ConversationSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('对话与策略')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _GroupHeader(icon: Icons.tune, title: '提示词策略',
              subtitle: '回复的推进方式、沉浸程度与字数控制'),
          _EntryTile(
            icon: Icons.auto_awesome,
            title: '推进与沉浸',
            subtitle: '强制推进 / 自由发展，克制 / 更强',
            onTap: () => _push(context, PromptStrategyPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.format_size,
            title: '字数控制',
            subtitle: '严格 80-120 字 / 适中 150-250 字 / 无限制 / 自定义',
            onTap: () => _push(context, PromptStrategyPage(controller: controller)),
          ),
          _GroupHeader(icon: Icons.account_tree, title: '摘要与上下文',
              subtitle: '长对话记忆、上下文保留与世界知识注入'),
          _EntryTile(
            icon: Icons.summarize,
            title: '自动摘要',
            subtitle: '触发轮数、按词数触发',
            onTap: () => _push(context, ConversationSummaryPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.content_paste_go,
            title: '上下文保留',
            subtitle: '历史条数、token 预算、世界知识条数与预算',
            onTap: () => _push(context, ConversationSummaryPage(controller: controller)),
          ),
          _GroupHeader(icon: Icons.send, title: '回复与发送',
              subtitle: '回车键行为、输入辅助与快速回复'),
          _EntryTile(
            icon: Icons.keyboard_return,
            title: '回车键行为',
            subtitle: '回车发送 / 回车换行',
            onTap: () => _push(context, ConversationSendPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.bolt,
            title: '输入辅助与快速回复',
            subtitle: '括号按钮、灵感附带摘要、重说策略、快速回复',
            onTap: () => _push(context, ConversationSendPage(controller: controller)),
          ),
          _GroupHeader(icon: Icons.rule, title: '消息与高级',
              subtitle: '消息删除、分叉与正则替换'),
          _EntryTile(
            icon: Icons.playlist_remove,
            title: '消息操作',
            subtitle: '任意删除对话项、从此处分叉',
            onTap: () => _push(context, ConversationAdvancedPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.find_replace,
            title: '命令宏与正则替换',
            subtitle: '动态占位符、正则替换规则',
            onTap: () => _push(context, ConversationAdvancedPage(controller: controller)),
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
