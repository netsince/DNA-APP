import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 对话与策略 → 摘要与上下文
///
/// 控制长对话的自动摘要、上下文保留条数 / token 预算与世界知识注入。
class ConversationSummaryPage extends StatefulWidget {
  const ConversationSummaryPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ConversationSummaryPage> createState() => _ConversationSummaryPageState();
}

class _ConversationSummaryPageState extends State<ConversationSummaryPage> {
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _wordCtrl;
  late bool _autoSummary;
  late final TextEditingController _ctxCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _stickyCtrl;
  late final TextEditingController _loreMaxEntriesCtrl;
  late final TextEditingController _loreBudgetTokensCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _autoSummary = s.autoSummaryPrompt;
    _summaryCtrl = TextEditingController(text: s.summaryTurnInterval.toString());
    _wordCtrl = TextEditingController(text: s.summaryWordThreshold.toString());
    _ctxCtrl = TextEditingController(text: s.maxContextMessages.toString());
    _tokenCtrl = TextEditingController(text: s.maxContextTokens.toString());
    _stickyCtrl = TextEditingController(text: s.loreStickyRounds.toString());
    _loreMaxEntriesCtrl = TextEditingController(text: s.loreMaxEntries.toString());
    _loreBudgetTokensCtrl = TextEditingController(text: s.loreBudgetTokens.toString());
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _wordCtrl.dispose();
    _ctxCtrl.dispose();
    _tokenCtrl.dispose();
    _stickyCtrl.dispose();
    _loreMaxEntriesCtrl.dispose();
    _loreBudgetTokensCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSummary() async {
    final turns = (int.tryParse(_summaryCtrl.text.trim()) ?? 200).clamp(10, 1000);
    _summaryCtrl.text = turns.toString();
    await widget.controller.saveSummarySettings(autoSummaryPrompt: _autoSummary, summaryTurnInterval: turns);
  }

  Future<void> _saveWord() async {
    final v = (int.tryParse(_wordCtrl.text.trim()) ?? 6000).clamp(0, 1000000);
    _wordCtrl.text = v.toString();
    await widget.controller.saveSummaryWordThreshold(v);
  }

  Future<void> _saveContext() async {
    final int v = (int.tryParse(_ctxCtrl.text.trim()) ?? 120).clamp(0, 1000);
    _ctxCtrl.text = v.toString();
    await widget.controller.saveMaxContextMessages(v);
  }

  Future<void> _saveTokens() async {
    final int v = (int.tryParse(_tokenCtrl.text.trim()) ?? 8000).clamp(0, 100000);
    _tokenCtrl.text = v.toString();
    await widget.controller.saveMaxContextTokens(v);
  }

  Future<void> _saveSticky() async {
    final int v = (int.tryParse(_stickyCtrl.text.trim()) ?? 3).clamp(0, 30);
    _stickyCtrl.text = v.toString();
    await widget.controller.saveLoreStickyRounds(v);
  }

  Future<void> _saveLoreMaxEntries() async {
    final int v = (int.tryParse(_loreMaxEntriesCtrl.text.trim()) ?? 8).clamp(0, 50);
    _loreMaxEntriesCtrl.text = v.toString();
    await widget.controller.saveLoreMaxEntries(v);
  }

  Future<void> _saveLoreBudgetTokens() async {
    final int v = (int.tryParse(_loreBudgetTokensCtrl.text.trim()) ?? 0).clamp(0, 100000);
    _loreBudgetTokensCtrl.text = v.toString();
    await widget.controller.saveLoreBudgetTokens(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const FitText('摘要与上下文')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const FitText('允许自动提示摘要'),
            value: _autoSummary,
            onChanged: (v) { setState(() => _autoSummary = v); _saveSummary(); },
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _summaryCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '触发轮数（按用户消息计）',
              hintText: '默认 200，范围 10-1000',
              isDense: true,
            ),
            onChanged: (_) => _saveSummary(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wordCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '按词数触发（距上次摘要新增字符数）',
              hintText: '默认 6000，范围 0-1000000，0 表示禁用',
              isDense: true,
            ),
            onChanged: (_) => _saveWord(),
          ),
          const Divider(),
          const FitText('上下文保留条数',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _ctxCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '单次请求最多携带的历史消息条数',
              hintText: '默认 120，范围 0-1000，0 表示不限',
              isDense: true,
            ),
            onChanged: (_) => _saveContext(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '历史消息 token 预算（精确逐条裁剪）',
              hintText: '默认 8000，范围 0-100000，0 表示不限',
              isDense: true,
            ),
            onChanged: (_) => _saveTokens(),
          ),
          const Divider(),
          const FitText('世界知识注入',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _stickyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '世界词条 sticky 轮数',
              hintText: '默认 3，范围 0-30，0 表示禁用',
              isDense: true,
            ),
            onChanged: (_) => _saveSticky(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loreMaxEntriesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '世界知识注入条数上限',
              hintText: '默认 8，范围 0-50，0 表示不限',
              isDense: true,
            ),
            onChanged: (_) => _saveLoreMaxEntries(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loreBudgetTokensCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '世界知识注入 token 预算',
              hintText: '默认 0（不限），超出自动裁剪并告警',
              isDense: true,
            ),
            onChanged: (_) => _saveLoreBudgetTokens(),
          ),
        ],
      ),
    );
  }
}
