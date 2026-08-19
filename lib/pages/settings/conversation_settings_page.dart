// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'conversation_advanced_page.dart';
import 'conversation_prompt_strategy_page.dart';
import 'conversation_send_page.dart';
import 'conversation_summary_page.dart';

/// 对话与策略：分类入口页。
///
/// 分组提供清晰详尽的副标题引导，彻底消除入门困惑。
class ConversationSettingsPage extends StatelessWidget {
  const ConversationSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('对话与策略')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          _EntryTile(
            icon: Icons.tune,
            title: '提示词策略',
            subtitle: '推进策略（主导/顺应/启发）与沉浸模式设置',
            onTap: () => _push(context, PromptStrategyPage(controller: controller)),
          ),
          const SizedBox(height: 10),
          _EntryTile(
            icon: Icons.account_tree_outlined,
            title: '摘要与上下文',
            subtitle: '阶段剧情摘要阈值、历史消息 Token 预算与世界书词条注入规则',
            onTap: () => _push(context, ConversationSummaryPage(controller: controller)),
          ),
          const SizedBox(height: 10),
          _EntryTile(
            icon: Icons.send_outlined,
            title: '回复与发送',
            subtitle: '回车键换行逻辑、动作描写括号快捷键、灵感生成与快速回复管理',
            onTap: () => _push(context, ConversationSendPage(controller: controller)),
          ),
          const SizedBox(height: 10),
          _EntryTile(
            icon: Icons.rule_outlined,
            title: '消息与高级能力',
            subtitle: '单条消息精准删除、剧情节点分支探索、动态占位宏与消息正则清洗',
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
