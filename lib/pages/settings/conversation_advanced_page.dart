// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';
import 'regex_rules_page.dart';

/// 设置 → 消息与高级。
///
/// **本次重构**(见 `SETTINGS_AUDIT.md`):
/// * 原 5 条提示全部超过 30 字(最长 71 字),现已压到一行以内;
/// * 宏变量说明(`{{char}}` 等)从设置项旁**移到折叠的说明区** ——
///   它属于参考手册,不该占用设置项的位置;
/// * 4 个开关按「消息操作」与「文本处理」分成两组,不再平铺。
class ConversationAdvancedPage extends StatefulWidget {
  const ConversationAdvancedPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationAdvancedPage> createState() =>
      _ConversationAdvancedPageState();
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
    final s = widget.controller.settings;

    return Scaffold(
      appBar: AppBar(title: const FitText('消息与高级')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 消息操作 =====
          SettingSection(
            icon: Icons.touch_app_outlined,
            title: '消息操作',
            description: '在消息上长按或右键时，能做哪些事。',
            children: <Widget>[
              SettingSwitch(
                title: '删除单条消息',
                subtitle: '只删掉选中的那一条。',
                value: _allowDeleteMessage,
                onChanged: (bool v) {
                  setState(() => _allowDeleteMessage = v);
                  widget.controller.saveAllowDeleteMessage(v);
                },
              ),
              SettingSwitch(
                title: '从任意处另起剧情',
                subtitle: '以某条消息为起点开一条新支线。',
                value: s.enableForking,
                onChanged: (bool v) {
                  setState(() {});
                  widget.controller.saveEnableForking(v);
                },
              ),
            ],
          ),

          // ===== 2. 文本处理 =====
          SettingSection(
            icon: Icons.auto_fix_high_outlined,
            title: '文本处理',
            description: 'AI 发来的内容在显示前会做哪些加工。',
            children: <Widget>[
              SettingSwitch(
                title: '解析动态占位符',
                subtitle: '支持 {{char}}、{{user}} 等写法。',
                value: s.enableCommandMacros,
                onChanged: (bool v) {
                  setState(() {});
                  widget.controller.saveEnableCommandMacros(v);
                },
              ),
              SettingHint(
                '常用写法：{{char}} 当前角色名，{{user}} 你的名字，'
                '{{roll 1-100}} 掷骰，{{random 甲|乙}} 随机二选一。',
                icon: Icons.help_outline,
              ),
              SettingSwitch(
                title: '正则文本清洗',
                subtitle: '按自定义规则过滤或替换消息内容。',
                value: s.enableRegexReplacement,
                onChanged: (bool v) {
                  setState(() {});
                  widget.controller.saveEnableRegexReplacement(v);
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.smAll,
                    side: BorderSide(
                      color:
                          Theme.of(context).colorScheme.outlineVariant
                              .withValues(alpha: AppAlpha.subtle),
                    ),
                  ),
                  contentPadding: AppInsets.group,
                  leading: const Icon(Icons.find_replace),
                  title: const FitText('管理清洗规则'),
                  subtitle: FitText('已配置 ${s.regexRules.length} 条'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RegexRulesPage(controller: widget.controller),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
