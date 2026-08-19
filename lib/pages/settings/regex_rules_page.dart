// ignore_for_file: deprecated_member_use
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
        title: FitText(existing == null ? '新增正则清洗规则' : '编辑正则清洗规则'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: patternController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '正则表达式 (Pattern)',
                  hintText: r'例如：\*[^*]+\* 或 (喵|喵呜)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: replacementController,
                decoration: const InputDecoration(
                  labelText: '替换为 (Replacement)',
                  hintText: '留空表示直接删除匹配内容',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: FitText(
                  '规则将按顺序依次应用于消息文本，语法错误的非法正则会被自动跳过。',
                  style: TextStyle(fontSize: 12),
                ),
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
            child: const FitText('保存规则'),
          ),
        ],
      ),
    );

    if (isValid == true) {
      final String pattern = patternController.text.trim();
      final String replacement = replacementController.text;
      if (pattern.isEmpty) return null;
      return RegexRule(
        id: existing?.id ?? newId(),
        pattern: pattern,
        replacement: replacement,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const FitText('消息正则清洗规则'),
        actions: <Widget>[
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.add),
            tooltip: '新增规则',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 顶部用途说明卡片 =====
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
                      Icon(Icons.auto_fix_high_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('正则清洗有什么用？', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FitText(
                    '在消息展示和保存前自动执行匹配替换。典型用途：\n'
                    '1. 过滤 AI 频繁输出的多余口癖（如每句话末尾的特定语气词）；\n'
                    '2. 消除星号动作描写（如把 *微笑* 清除）；\n'
                    '3. 自动修正常见错别字或屏蔽敏感词。',
                    style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (_rules.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: <Widget>[
                  Icon(Icons.find_replace, size: 40, color: cs.outline),
                  const SizedBox(height: 10),
                  const FitText('暂无清洗规则'),
                  const SizedBox(height: 6),
                  FitText('点击右上角【+】或下方按钮创建第一条规则', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const FitText('新增规则'),
                  ),
                ],
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _rules.length,
              onReorder: (int oldIndex, int newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final RegexRule item = _rules.removeAt(oldIndex);
                  _rules.insert(newIndex, item);
                });
                _persist();
              },
              itemBuilder: (BuildContext context, int index) {
                final RegexRule rule = _rules[index];
                return Card(
                  key: ValueKey<String>(rule.id),
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: cs.primaryContainer,
                      child: FitText(
                        '${index + 1}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                      ),
                    ),
                    title: FitText(
                      '匹配：${rule.pattern}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                    ),
                    subtitle: FitText(
                      rule.replacement.isEmpty ? '替换为：[删除匹配内容]' : '替换为：${rule.replacement}',
                      style: ts.bodySmall?.copyWith(color: cs.outline),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: '编辑',
                          onPressed: () => _edit(rule),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: '删除',
                          onPressed: () => _delete(rule),
                        ),
                        const Icon(Icons.drag_handle, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      floatingActionButton: _rules.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const FitText('新增清洗规则'),
            )
          : null,
    );
  }
}
