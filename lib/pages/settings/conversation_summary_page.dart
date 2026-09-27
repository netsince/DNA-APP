// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_collapsible.dart';
import 'package:dna/widgets/setting_section.dart';

/// 设置 → 剧情摘要与上下文。
///
/// **本次重构**(见 `SETTINGS_AUDIT.md`):
/// * 7 个文本框 → 可折叠数值项,收起态只显示「名称 + 当前值」;
/// * 范围由滑块的物理边界表达,删掉「默认 200,范围 10-1000」这类描述性文案;
/// * 世界书参数**已移出本页** —— 它们属于世界书,不属于摘要。
class ConversationSummaryPage extends StatefulWidget {
  const ConversationSummaryPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationSummaryPage> createState() =>
      _ConversationSummaryPageState();
}

class _ConversationSummaryPageState extends State<ConversationSummaryPage> {
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _loreBudgetCtrl;
  late bool _autoSummary;
  late int _turns;
  late int _words;
  late int _ctxMessages;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _autoSummary = s.autoSummaryPrompt;
    _turns = s.summaryTurnInterval;
    _words = s.summaryWordThreshold;
    _ctxMessages = s.maxContextMessages;
    _tokenCtrl =
        TextEditingController(text: s.maxContextTokens.toString());
    _loreBudgetCtrl =
        TextEditingController(text: s.loreBudgetTokens.toString());
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _loreBudgetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('剧情摘要与上下文')),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 1. 剧情摘要 =====
          SettingSection(
            icon: Icons.history_edu_outlined,
            title: '剧情摘要',
            description: '对话变长后，让 AI 记住前文。',
            children: <Widget>[
              SettingSwitch(
                title: '自动生成摘要',
                subtitle: '达到下面的条件时，提示 AI 总结前文。',
                value: _autoSummary,
                onChanged: (bool v) {
                  setState(() => _autoSummary = v);
                  widget.controller.saveSummarySettings(
                    autoSummaryPrompt: v,
                    summaryTurnInterval: _turns,
                  );
                },
              ),
              CollapsibleNumberSetting(
                title: '达到多少轮对话时摘要',
                value: _turns,
                min: 10,
                max: 1000,
                step: 10,
                unit: '轮',
                helper: '计数的是对话轮数（一问一答算两轮），不是消息条数。',
                onChanged: (int v) {
                  setState(() => _turns = v);
                  widget.controller.saveSummarySettings(
                    autoSummaryPrompt: _autoSummary,
                    summaryTurnInterval: v,
                  );
                },
              ),
              CollapsibleNumberSetting(
                title: '新增多少字后摘要',
                value: _words,
                min: 0,
                max: 50000,
                step: 500,
                unit: '字',
                zeroLabel: '不限',
                helper: '与上面的轮数条件满足任意一个就会触发。填 0 表示只看轮数。',
                onChanged: (int v) {
                  setState(() => _words = v);
                  widget.controller.saveSummaryWordThreshold(v);
                },
              ),
            ],
          ),

          // ===== 2. 携带多少历史 =====
          SettingSection(
            icon: Icons.inventory_2_outlined,
            title: '携带多少历史',
            description: '发给 AI 的对话范围，超出从最早的开始丢。',
            children: <Widget>[
              CollapsibleNumberSetting(
                title: '最多带上多少条消息',
                value: _ctxMessages,
                min: 0,
                max: 500,
                step: 10,
                unit: '条',
                zeroLabel: '不限',
                helper: '只影响发送给 AI 的范围，聊天记录本身不会丢。',
                onChanged: (int v) {
                  setState(() => _ctxMessages = v);
                  widget.controller.saveMaxContextMessages(v);
                },
              ),
              CollapsibleTextSetting(
                title: '最多占用多少记忆容量',
                controller: _tokenCtrl,
                unit: 'Token',
                zeroLabel: '不限',
                helper: 'Token 是 AI 计量文字用量的单位，1 个汉字约等于 1 个 Token。'
                    '范围太大或太小都不合适，拿不准就保持默认。',
                onSubmitted: (int v) => widget.controller.saveMaxContextTokens(v),
              ),
            ],
          ),

          // ===== 3. 世界书注入（已从本页移出的说明） =====
          SettingSection(
            icon: Icons.public_outlined,
            title: '世界书注入',
            description: '控制世界观词条被激活后如何注入对话。',
            children: <Widget>[
              SettingHint(
                '词条的编写与管理在「世界」页；这里只控制全局的生效范围与容量。',
                icon: Icons.info_outline,
              ),
              CollapsibleNumberSetting(
                title: '词条命中后持续几轮',
                value: widget.controller.settings.loreStickyRounds,
                min: 0,
                max: 30,
                unit: '轮',
                zeroLabel: '不持续',
                helper: '词条被关键词命中后，在接下来这几轮内持续生效，避免中途「忘设定」。',
                onChanged: (int v) {
                  setState(() {});
                  widget.controller.saveLoreStickyRounds(v);
                },
              ),
              CollapsibleNumberSetting(
                title: '一次最多注入几条词条',
                value: widget.controller.settings.loreMaxEntries,
                min: 0,
                max: 50,
                unit: '条',
                zeroLabel: '不限',
                helper: '注入太多会冲淡人设，建议保持默认的少量。',
                onChanged: (int v) {
                  setState(() {});
                  widget.controller.saveLoreMaxEntries(v);
                },
              ),
              CollapsibleTextSetting(
                title: '世界书最多占用多少容量',
                controller: _loreBudgetCtrl,
                unit: 'Token',
                zeroLabel: '不限',
                helper: '超出时优先丢掉优先级低的词条。',
                onSubmitted: (int v) => widget.controller.saveLoreBudgetTokens(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
