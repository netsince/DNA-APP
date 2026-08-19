// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'package:dna/widgets/fit_text.dart';

/// 对话与策略 → 摘要与上下文。
///
/// 控制长对话的自动摘要、上下文保留条数 / Token 预算与世界知识注入。
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const FitText('摘要与上下文')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 1. 剧情自动摘要 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.history_edu, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('阶段剧情摘要', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '当对话轮数或累计字数达到阈值时自动生成历史摘要，保持角色长期记忆。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const FitText('允许自动提示生成摘要'),
                    value: _autoSummary,
                    onChanged: (v) {
                      setState(() => _autoSummary = v);
                      _saveSummary();
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _summaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '按对话轮数触发（轮）',
                      hintText: '默认 200，范围 10-1000',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveSummary(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _wordCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '按新增字数触发（字符）',
                      hintText: '默认 6000，填 0 表示不限',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveWord(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 2. 历史上下文与 Token 预算 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.inventory_2_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('历史上下文限制', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '条数与 Token 预算双重限制，请求时会自动从最旧的消息逐条裁剪。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '最多携带的历史消息条数',
                      hintText: '默认 120，填 0 表示不限条数',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveContext(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '历史消息 Token 预算上限',
                      hintText: '默认 8000，填 0 表示不限 Token',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveTokens(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== 3. 世界书知识库注入 =====
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
                  Row(
                    children: <Widget>[
                      Icon(Icons.public_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('世界书词条注入规则', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FitText(
                    '控制世界背景与设定词条被关键词激活后的生效范围与注入量。',
                    style: ts.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stickyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '词条附着持续轮数',
                      hintText: '触发后在接下来的几轮内持续生效，默认 3 轮',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveSticky(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _loreMaxEntriesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '单次请求最多注入词条数',
                      hintText: '默认最多 8 条，避免词条过多冲淡人设',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveLoreMaxEntries(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _loreBudgetTokensCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '世界书 Token 预算上限',
                      hintText: '默认 0（不限），超出时优先截断低优先级词条',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _saveLoreBudgetTokens(),
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
