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
/// 每组一个入口，点击进入对应的设置页，避免把所有设置项平铺在一个页面。
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
          _EntryTile(
            icon: Icons.tune,
            title: '提示词策略',
            onTap: () => _push(context, PromptStrategyPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.account_tree,
            title: '摘要与上下文',
            onTap: () => _push(context, ConversationSummaryPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.send,
            title: '回复与发送',
            onTap: () => _push(context, ConversationSendPage(controller: controller)),
          ),
          _EntryTile(
            icon: Icons.rule,
            title: '消息与高级',
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
