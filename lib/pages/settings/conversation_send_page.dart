// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'quick_replies_page.dart';

/// 对话与策略 → 回复与发送。
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('回复与发送')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 键盘与输入辅助 =====
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
                  FitText('键盘与输入辅助', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  FitText('回车键按键行为', style: ts.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  RadioGroup<String>(
                    groupValue: widget.controller.settings.enterToSend ? 'send' : 'newline',
                    onChanged: (String? v) {
                      if (v == null) return;
                      setState(() {});
                      widget.controller.saveEnterToSend(v == 'send');
                    },
                    child: Column(
                      children: const <Widget>[
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
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('输入栏显示括号快捷键'),
                    subtitle: const FitText('在输入框旁放置「（）」按钮，一键插入括号并聚焦中间，方便撰写动作与神态描写。'),
                    value: widget.controller.settings.showParenButton,
                    onChanged: (v) {
                      setState(() {});
                      widget.controller.saveShowParenButton(v);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 灵感与重试 =====
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
                  FitText('请求与灵感策略', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('灵感建议附带最近摘要'),
                    subtitle: const FitText('生成灵感候选项时一并携带剧情摘要，建议更贴合上下文（默认关闭以节省 Token）。'),
                    value: _inspireSummary,
                    onChanged: (v) {
                      setState(() => _inspireSummary = v);
                      _saveInspire();
                    },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('重说请求按顺序单次执行'),
                    subtitle: const FitText('开启后重说会按顺序单次排队发起，关闭则并发请求 3 次。'),
                    value: _retrySeq,
                    onChanged: (v) {
                      setState(() => _retrySeq = v);
                      _saveRetry();
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 快捷短语 =====
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Icon(Icons.bolt, color: cs.primary),
              title: const FitText('快速回复管理'),
              subtitle: const FitText('自定义聊天输入栏上方展示的常用一键发送短语。'),
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
          ),
        ],
      ),
    );
  }
}
