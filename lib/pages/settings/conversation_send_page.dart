// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';
import 'quick_replies_page.dart';

/// 对话与策略 → 回复与发送。
///
/// **本次改造**(见 `SETTINGS_AUDIT.md`):
/// * 3 处手写 `Card > Padding > Column` 样板 → `SettingSection` 组件族;
/// * 每个分组标题带图标(规矩 4);
/// * 2 条超长提示(41 字 / 38 字)压到 10 字以内:
///   说明从 `subtitle` 移到开关右侧的 `description`,开关行仍是单行;
/// * 回车键行为保留单选项,多行详细说明(补充键位/连续发送)移到 `SettingHint`。
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
    final s = widget.controller.settings;

    return Scaffold(
      appBar: AppBar(title: const FitText('回复与发送')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 键盘与输入辅助 =====
          SettingSection(
            icon: Icons.keyboard_outlined,
            title: '键盘与输入辅助',
            description: '回车键做什么，输入栏有哪些快捷按钮。',
            children: <Widget>[
              FitText('回车键按键行为', style: AppTextStyles.body(Theme.of(context))),
              AppSpacing.hXs,
              RadioGroup<String>(
                groupValue: s.enterToSend ? 'send' : 'newline',
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
              SettingHint(
                '补充：长按发送按钮可以连续发送多条。',
                icon: Icons.info_outline,
              ),
              SettingSwitch(
                title: '括号快捷键',
                description: '只影响输入栏',
                value: s.showParenButton,
                onChanged: (bool v) {
                  setState(() {});
                  widget.controller.saveShowParenButton(v);
                },
              ),
            ],
          ),

          // ===== 2. 请求与灵感策略 =====
          SettingSection(
            icon: Icons.auto_awesome_outlined,
            title: '请求与灵感策略',
            description: '重说怎么发，灵感建议要不要参考剧情。',
            children: <Widget>[
              SettingSwitch(
                title: '灵感附带最近摘要',
                description: '更贴合上下文',
                value: _inspireSummary,
                onChanged: (bool v) {
                  setState(() => _inspireSummary = v);
                  _saveInspire();
                },
              ),
              SettingSwitch(
                title: '重说按顺序单次发起',
                description: '减轻服务压力',
                value: _retrySeq,
                onChanged: (bool v) {
                  setState(() => _retrySeq = v);
                  _saveRetry();
                },
              ),
              SettingHint(
                '关闭「重说按顺序单次发起」时，会同时并发请求 3 次。',
                icon: Icons.info_outline,
              ),
            ],
          ),

          // ===== 3. 快速回复 =====
          SettingSection(
            icon: Icons.bolt_outlined,
            title: '快速回复',
            description: '输入栏上方的常用短句按钮。',
            children: <Widget>[
              SettingTile(
                title: '管理快速回复',
                subtitle: '添加、编辑或删除常用短句。',
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
        ],
      ),
    );
  }
}
