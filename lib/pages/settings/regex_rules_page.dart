// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../state/app_controller.dart';
import '../../utils/id_utils.dart';
import '../../utils/message_processor.dart';
import 'package:dna/widgets/app_empty_state.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

/// 消息清洗规则管理页。
///
/// **本次改造**(见 `SETTINGS_AUDIT.md`):
/// * 顶部用途说明卡片(89 字整段)改写为 `SettingSection` 短说明
///   `description` + 三条 `SettingHint` 示例;
/// * 首页空状态改用 `AppEmptyState` 组件;
/// * 列表项卡片样板改用令牌,并去掉「正则」黑话:
///   标题改为「匹配的文字」,弹窗标签改为中文说法。
///
/// **不套 `SettingSection` 的部分**:下方是可拖动排序的**规则条目列表**
/// (条目集合,非设置项堆叠),按规矩 1 的豁免说明保留列表结构;
/// 但它的卡片细节(圆角/描边/间距)已统一改用设计令牌。
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
        title: FitText(existing == null ? '新增清洗规则' : '编辑清洗规则'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: patternController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '要匹配的文字',
                  hintText: r'例如：\*[^*]+\* 或 (喵|喵呜)',
                  helperText: '用「模式」描述想找的文字，方括号和竖线表示可选',
                  border: OutlineInputBorder(),
                ),
              ),
              AppSpacing.hMd,
              TextField(
                controller: replacementController,
                decoration: const InputDecoration(
                  labelText: '替换为',
                  hintText: '留空表示直接删除匹配内容',
                  border: OutlineInputBorder(),
                ),
              ),
              AppSpacing.hMd,
              const Align(
                alignment: Alignment.centerLeft,
                child: FitText(
                  '规则按从上到下的顺序生效，写错的规则会被自动跳过。',
                  style: TextStyle(fontSize: AppFontSize.caption),
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const FitText('消息清洗规则'),
        actions: <Widget>[
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.add),
            tooltip: '新增规则',
          ),
        ],
      ),
      body: ListView(
        padding: AppInsets.page,
        children: <Widget>[
          // ===== 用途说明(不再用手写卡片样板) =====
          SettingSection(
            icon: Icons.auto_fix_high_outlined,
            title: '清洗规则能做什么',
            description: '让 AI 的回复显示得更干净。',
            children: <Widget>[
              SettingHint(
                '1. 去掉每句话末尾多余的口癖',
                icon: Icons.filter_alt_outlined,
              ),
              SettingHint('2. 去掉 *星号* 包起来的动作描写'),
              SettingHint('3. 替换常写错的字，或屏蔽不想看到的词'),
            ],
          ),

          AppSpacing.hLg,

          // ===== 规则列表（条目集合，非设置项堆叠）=====
          if (_rules.isEmpty)
            AppEmptyState(
              icon: Icons.find_replace,
              title: '还没有清洗规则',
              description: '创建第一条规则，让回复变干净。',
              actionLabel: '新增规则',
              actionIcon: Icons.add,
              onAction: _add,
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
                  elevation: AppElevation.flat,
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  shape: AppBorder.secondaryShape(cs),
                  child: ListTile(
                    contentPadding: AppInsets.group,
                    leading: CircleAvatar(
                      radius: AppSpacing.lg,
                      backgroundColor: cs.primaryContainer,
                      child: FitText(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: AppWeight.medium,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: FitText(
                      '匹配：${rule.pattern}',
                      style: const TextStyle(
                        fontWeight: AppWeight.medium,
                        fontFamily: 'monospace',
                      ),
                    ),
                    subtitle: FitText(
                      rule.replacement.isEmpty
                          ? '替换为：删除匹配内容'
                          : '替换为：${rule.replacement}',
                      style: AppTextStyles.caption(theme).copyWith(
                        color: cs.outline,
                      ),
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
                        const Icon(Icons.drag_handle, size: AppSize.iconCard),
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
