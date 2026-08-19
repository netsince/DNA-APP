// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'regex_rules_page.dart';

/// 对话与策略 → 消息与高级。
///
/// 控制消息删除 / 分叉、命令宏与正则替换等进阶能力。
class ConversationAdvancedPage extends StatefulWidget {
  const ConversationAdvancedPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationAdvancedPage> createState() => _ConversationAdvancedPageState();
}

class _ConversationAdvancedPageState extends State<ConversationAdvancedPage> {
  bool _allowDeleteMessage = false;

  @override
  void initState() {
    super.initState();
    _allowDeleteMessage = widget.controller.settings.allowDeleteMessage;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('消息与高级')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 消息管理能力 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('消息编辑与分支能力', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('单条消息精准删除'),
                    subtitle: const FitText('长按或右键消息时显示「删除本条」选项，仅移除选中的单条消息。'),
                    value: _allowDeleteMessage,
                    onChanged: (v) {
                      setState(() => _allowDeleteMessage = v);
                      widget.controller.saveAllowDeleteMessage(v);
                    },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('开启节点剧情分叉'),
                    subtitle: const FitText('右键消息可选择「从此处分叉」，从历史节点另起新会话探索不同支线。'),
                    value: widget.controller.settings.enableForking,
                    onChanged: (v) {
                      setState(() {});
                      widget.controller.saveEnableForking(v);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 文本增强与动态处理 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FitText('文本增强与动态宏', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('动态占位宏变量（Command Macros）'),
                    subtitle: const FitText('支持在人设与对话中解析 {{char}}、{{user}}、{{roll 1-100}}、{{random 选项A|选项B}} 等动态占位符。'),
                    value: widget.controller.settings.enableCommandMacros,
                    onChanged: (v) {
                      setState(() {});
                      widget.controller.saveEnableCommandMacros(v);
                    },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('消息正则文本清洗'),
                    subtitle: const FitText('自动按正则表达式过滤或替换消息内容（如清除口癖、特定标记或错别字）。'),
                    value: widget.controller.settings.enableRegexReplacement,
                    onChanged: (v) {
                      setState(() {});
                      widget.controller.saveEnableRegexReplacement(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: const Icon(Icons.find_replace),
                    title: const FitText('管理正则替换规则'),
                    subtitle: FitText('已配置 ${widget.controller.settings.regexRules.length} 条过滤/替换规则'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RegexRulesPage(controller: widget.controller),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
