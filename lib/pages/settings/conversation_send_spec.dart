/// 设置 → 回复与发送（配置驱动版）。
///
/// ## 为什么排版格式三项是「动作」而不是「开关」
///
/// 它们写的是 `promptStrategy` 这个复合对象的子字段。`promptStrategy` 在
/// `AppSettings.toJson()` 里是对象、在 `settingsKeyKinds` 里是 object：
/// 挂成 SettingToggle 会被声明校验判成类型不符（toggle → boolean），
/// 渲染时 `_rawValue() as bool? ?? default` 也会把 Map 强转炸掉。
/// 所以这里用 SettingAction 包一个 SettingSwitch，读走
/// `controller.settings.promptStrategy`，写走一次 `savePromptStrategy` ——
/// 与提示词策略页共用同一份字段。
///
/// ## 回车键为什么是单选行
///
/// 字段虽然是 bool，但用户面对的是「回车做什么」这组互斥行为，两个选项各带
/// 一句完整解释（Shift 反向），分段按钮塞不下，所以用 `ChoiceLayout.radioList`。
///
/// ## 写入时机
///
/// 开关/单选一改即存（immediate），段落数是回车或点按钮才写（onSubmit）——
/// 与改动前的交互一致，所以两条路径都保持人手触发。
library;

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/setting_section.dart';
import 'quick_replies_page.dart';
import 'spec/settings_spec.dart';

// ---- 文案常量 ----
//
// 动作项的 title/subtitle 在声明里只服务搜索与断言，真正渲染的是 builder；
// 两边共用同一份常量，免得同一条文案写两遍后各改各的。

const String _enterToSendTitle = '回车键按键行为';
const String _enterToSendSubtitle = '输入栏按回车时做什么';
const String _enterToSendHint = '补充：长按发送按钮可以连续发送多条。';
const String _sendOnEnterLabel = '回车发送，Shift + 回车换行';
const String _newlineOnEnterLabel = '回车换行，Shift + 回车发送';

const String _parenTitle = '括号快捷键';
const String _parenSubtitle = '只影响输入栏';

const String _inspireTitle = '灵感附带最近摘要';
const String _inspireSubtitle = '更贴合上下文';

const String _retryTitle = '重说按顺序单次发起';
const String _retrySubtitle = '减轻服务压力';
const String _retryHint = '关闭「重说按顺序单次发起」时，会同时并发请求 3 次。';

const String _quickRepliesTitle = '管理快速回复';
const String _quickRepliesSubtitle = '添加、编辑或删除常用短句。';

// 这三条短说明在旧交互里是行内（开关右侧同一行），所以 builder 走
// SettingSwitch.description；声明里的 subtitle 只为搜索，文案共用同一份。
const String _italicTitle = '旁白用斜体';
const String _italicNote = '动作与描写用 *斜体*';

const String _quoteTitle = '台词加引号';
const String _quoteNote = '台词用「」包裹';

const String _markdownTitle = '允许 Markdown';
const String _markdownNote = '加粗、列表等语法';

const String _paragraphsTitle = '单条回复最大段落数';
const String _paragraphsSubtitle = '0 = 不限制';
const String _paragraphsApplyLabel = '应用段落数';

/// 单条回复最大段落数：输入框 + 「应用」按钮，回车与点按钮都会落盘。
///
/// 保留手写控件而不是 SettingInt，是因为它写的是 PromptStrategy 的子字段，
/// 没有标量 key 可挂；数值语义（0 = 不限、负数归零）沿用原实现。
class _MaxParagraphsField extends StatefulWidget {
  const _MaxParagraphsField({required this.controller});

  final AppController controller;

  @override
  State<_MaxParagraphsField> createState() => _MaxParagraphsFieldState();
}

class _MaxParagraphsFieldState extends State<_MaxParagraphsField> {
  late final TextEditingController _text = TextEditingController(
    text: _initialText(
      widget.controller.settings.promptStrategy.formatMaxParagraphs,
    ),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final int parsed = int.tryParse(_text.text.trim()) ?? 0;
    await widget.controller.savePromptStrategy(
      widget.controller.settings.promptStrategy.copyWith(
        formatMaxParagraphs: parsed < 0 ? 0 : parsed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: TextField(
            controller: _text,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: _paragraphsTitle,
              hintText: _paragraphsSubtitle,
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (String _) => _apply(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.tonal(
          onPressed: _apply,
          child: const FitText(_paragraphsApplyLabel),
        ),
      ],
    );
  }

  /// 0 在界面上的写法是「留空」，不是字面上的 0。
  String _initialText(int value) => value == 0 ? '' : '$value';
}

/// 回复与发送页的完整声明。
final FieldsEntry conversationSendEntry = FieldsEntry(
  id: 'conversationSend',
  groupId: SettingsGroupId.dialogue,
  icon: Icons.send_outlined,
  title: '回复与发送',
  subtitle: '回车键行为、灵感生成与快速回复',
  sections: <SettingSectionSpec>[
    SettingSectionSpec(
      id: 'conversationSend.keyboard',
      icon: Icons.keyboard_outlined,
      title: '键盘与输入辅助',
      items: <SettingItemSpec>[
        SettingChoice<bool>(
          id: 'conversationSend.enterToSend',
          title: _enterToSendTitle,
          subtitle: _enterToSendSubtitle,
          hint: _enterToSendHint,
          key: 'enterToSend',
          defaultValue: true,
          layout: ChoiceLayout.radioList,
          options: const <ChoiceOption<bool>>[
            ChoiceOption<bool>(value: true, label: _sendOnEnterLabel),
            ChoiceOption<bool>(value: false, label: _newlineOnEnterLabel),
          ],
        ),
        SettingToggle(
          id: 'conversationSend.showParenButton',
          title: _parenTitle,
          // 旧版是行内短说明（开关右侧同一行），降级成 subtitle 会多占一行。
          inlineNote: _parenSubtitle,
          key: 'showParenButton',
          defaultValue: true,
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'conversationSend.strategy',
      icon: Icons.auto_awesome_outlined,
      title: '请求与灵感策略',
      description: '灵感建议是否参考剧情。',
      items: <SettingItemSpec>[
        SettingToggle(
          id: 'conversationSend.inspirationIncludeSummary',
          title: _inspireTitle,
          inlineNote: _inspireSubtitle,
          key: 'inspirationIncludeSummary',
        ),
        SettingToggle(
          id: 'conversationSend.retrySequential',
          title: _retryTitle,
          inlineNote: _retrySubtitle,
          hint: _retryHint,
          key: 'retrySequential',
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'conversationSend.quickReply',
      icon: Icons.bolt_outlined,
      title: '快速回复',
      description: '输入栏上方的常用短句按钮。',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'conversationSend.manageQuickReplies',
          title: _quickRepliesTitle,
          subtitle: _quickRepliesSubtitle,
          builder: (BuildContext context, AppController controller) =>
              SettingTile(
                title: _quickRepliesTitle,
                subtitle: _quickRepliesSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext _) =>
                        QuickRepliesPage(controller: controller),
                  ),
                ),
              ),
        ),
      ],
    ),
    SettingSectionSpec(
      id: 'conversationSend.format',
      icon: Icons.format_paint_outlined,
      title: '排版格式',
      items: <SettingItemSpec>[
        SettingAction(
          id: 'conversationSend.formatActionItalic',
          title: _italicTitle,
          subtitle: _italicNote,
          builder: (BuildContext context, AppController controller) =>
              SettingSwitch(
                title: _italicTitle,
                description: _italicNote,
                value: controller.settings.promptStrategy.formatActionItalic,
                onChanged: (bool v) => controller.savePromptStrategy(
                  controller.settings.promptStrategy.copyWith(
                    formatActionItalic: v,
                  ),
                ),
              ),
        ),
        SettingAction(
          id: 'conversationSend.formatQuoteDialogue',
          title: _quoteTitle,
          subtitle: _quoteNote,
          builder: (BuildContext context, AppController controller) =>
              SettingSwitch(
                title: _quoteTitle,
                description: _quoteNote,
                value: controller.settings.promptStrategy.formatQuoteDialogue,
                onChanged: (bool v) => controller.savePromptStrategy(
                  controller.settings.promptStrategy.copyWith(
                    formatQuoteDialogue: v,
                  ),
                ),
              ),
        ),
        SettingAction(
          id: 'conversationSend.formatMarkdown',
          title: _markdownTitle,
          subtitle: _markdownNote,
          builder: (BuildContext context, AppController controller) =>
              SettingSwitch(
                title: _markdownTitle,
                description: _markdownNote,
                value: controller.settings.promptStrategy.formatMarkdown,
                onChanged: (bool v) => controller.savePromptStrategy(
                  controller.settings.promptStrategy.copyWith(formatMarkdown: v),
                ),
              ),
        ),
        SettingAction(
          id: 'conversationSend.formatMaxParagraphs',
          title: _paragraphsTitle,
          subtitle: _paragraphsSubtitle,
          builder: (BuildContext context, AppController controller) =>
              _MaxParagraphsField(controller: controller),
        ),
      ],
    ),
  ],
);
