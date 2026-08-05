import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../utils/id_utils.dart';
import '../../utils/message_processor.dart';
import 'package:dna/widgets/fit_text.dart';

/// 正则替换规则管理页。
///
/// 每条规则包含「正则表达式」与「替换为」两栏，按顺序依次应用于消息文本。
class RegexRulesPage extends StatefulWidget {
  const RegexRulesPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<RegexRulesPage> createState() => _RegexRulesPageState();
}

class _RegexRulesPageState extends State<RegexRulesPage> {
  late List<RegexRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = List<RegexRule>.of(widget.controller.settings.regexRules);
  }

  Future<void> _persist() => widget.controller.saveRegexRules(_rules);

  Future<void> _add() async {
    final RegexRule? rule = await _editRule(null);
    if (rule != null) {
      setState(() => _rules.add(rule));
      await _persist();
    }
  }

  Future<void> _edit(RegexRule rule) async {
    final RegexRule? updated = await _editRule(rule);
    if (updated != null) {
      setState(() {
        final int idx = _rules.indexWhere((RegexRule r) => r.id == rule.id);
        if (idx >= 0) {
          _rules[idx] = updated;
        }
      });
      await _persist();
    }
  }

  Future<void> _delete(RegexRule rule) async {
    setState(() => _rules.removeWhere((RegexRule r) => r.id == rule.id));
    await _persist();
  }

  Future<RegexRule?> _editRule(RegexRule? existing) async {
    final TextEditingController patternController =
        TextEditingController(text: existing?.pattern ?? '');
    final TextEditingController replacementController =
        TextEditingController(text: existing?.replacement ?? '');
    final bool? isValid = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: FitText(existing == null ? '新增正则规则' : '编辑正则规则'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: patternController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '正则表达式',
                  hintText: r'例如：\s{2,}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: replacementController,
                decoration: const InputDecoration(
                  labelText: '替换为',
                  hintText: '替换后的文本',
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: FitText('规则将按顺序应用于消息文本，非法正则会被自动跳过。', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const FitText('保存'),
          ),
        ],
      ),
    );
    if (isValid != true || patternController.text.trim().isEmpty) {
      return null;
    }
    return RegexRule(
      id: existing?.id ?? newId(),
      pattern: patternController.text.trim(),
      replacement: replacementController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('正则替换规则')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const FitText(
              '这里的正则规则会在发送消息时按顺序对文本进行替换，可用于修正格式、统一人称、清理重复标点等。'
              '需要先在「对话与策略」中启用「正则替换」。',
            ),
          ),
          const SizedBox(height: 12),
          for (final RegexRule rule in _rules)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: FitText(rule.pattern,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: FitText('替换为：${rule.replacement.isEmpty ? "(空)" : rule.replacement}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _edit(rule),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(rule),
                    ),
                  ],
                ),
              ),
            ),
          if (_rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: FitText('暂无正则规则，点击下方按钮添加。',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const FitText('新增规则'),
          ),
        ],
      ),
    );
  }
}
