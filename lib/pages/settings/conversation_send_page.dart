import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'quick_replies_page.dart';

/// 对话与策略 → 回复与发送
///
/// 控制回车键行为、输入辅助、灵感附带摘要、重说策略与快速回复。
class ConversationSendPage extends StatefulWidget {
  const ConversationSendPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationSendPage> createState() => _ConversationSendPageState();
}

class _ConversationSendPageState extends State<ConversationSendPage> {
  bool _retrySeq = false;
  bool _inspireSummary = false;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _retrySeq = s.retrySequential;
    _inspireSummary = s.inspirationIncludeSummary;
  }

  Future<void> _saveRetry() =>
      widget.controller.saveRetryStrategy(retrySequential: _retrySeq);
  Future<void> _saveInspire() =>
      widget.controller.saveInspirationSettings(includeSummary: _inspireSummary);

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('回复与发送')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FitText(
              '回车键行为',
              style: ts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          RadioGroup<String>(
            groupValue: widget.controller.settings.enterToSend ? 'send' : 'newline',
            onChanged: (String? v) {
              if (v == null) return;
              setState(() {});
              widget.controller.saveEnterToSend(v == 'send');
            },
            child: const Column(
              children: <Widget>[
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'send',
                  title: FitText('回车发送，Shift + 回车换行'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'newline',
                  title: FitText('回车换行，Shift + 回车发送'),
                ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('输入框旁显示括号按钮'),
            subtitle: const FitText('在聊天输入框旁显示「（）」按钮，点击在末尾追加括号并把光标置于中间。'),
            value: widget.controller.settings.showParenButton,
            onChanged: (v) {
              setState(() {});
              widget.controller.saveShowParenButton(v);
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('灵感附带最近摘要'),
            subtitle: const FitText('开启后会在生成灵感时附带最近摘要。默认关闭以节省 token。'),
            value: _inspireSummary,
            onChanged: (v) { setState(() => _inspireSummary = v); _saveInspire(); },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('多个请求按顺序单次执行'),
            subtitle: const FitText('开启后重说会顺序发送三次请求。关闭则并发请求三次。'),
            value: _retrySeq,
            onChanged: (v) { setState(() => _retrySeq = v); _saveRetry(); },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bolt),
            title: const FitText('快速回复'),
            subtitle: const FitText('管理聊天输入栏上方的一键发送按钮'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      QuickRepliesPage(controller: widget.controller),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
