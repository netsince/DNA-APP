import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'regex_rules_page.dart';

/// 对话与策略 → 消息与高级
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
    return Scaffold(
      appBar: AppBar(title: const FitText('消息与高级')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('任意删除对话项'),
            subtitle: const FitText('开启后，在聊天页长按/右键单条消息会显示「删除本条」，仅删除该条消息。'),
            value: _allowDeleteMessage,
            onChanged: (v) {
              setState(() => _allowDeleteMessage = v);
              widget.controller.saveAllowDeleteMessage(v);
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('打开从此处分叉'),
            subtitle: const FitText('开启后，在聊天页右键对方的气泡会出现「从此处分叉」选项，可把该处之后的内容另起新会话继续。'),
            value: widget.controller.settings.enableForking,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveEnableForking(v);
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('命令宏'),
            subtitle: const FitText('启用 {{char}}/{{user}}/{{roll}}/{{random}} 等动态占位符。默认启用。'),
            value: widget.controller.settings.enableCommandMacros,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveEnableCommandMacros(v);
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('正则替换'),
            subtitle: const FitText('按规则对消息进行正则替换。默认启用。'),
            value: widget.controller.settings.enableRegexReplacement,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveEnableRegexReplacement(v);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.find_replace),
            title: const FitText('正则替换规则'),
            subtitle: FitText('管理正则替换规则（${widget.controller.settings.regexRules.length} 条）'),
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
    );
  }
}
