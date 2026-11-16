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

  /// 打开规则编辑表单。
  ///
  /// 容器从 dialog 改成 bottom sheet（审计 3.2）：这是填写表单，不是
  /// 需要立刻拍板的决定；sheet 还顺手解决了 dialog 宽度写死 360 的问题。
  Future<RegexRule?> _editRule(RegexRule? existing) {
    return showModalBottomSheet<RegexRule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          _RegexRuleSheet(existing: existing),
    );
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
              // 新 API：onReorderItem 的 newIndex 已经按「移除后下标」调整过，
              // 所以这里不能再做 oldIndex < newIndex 的 -1 修正（会双重调整）。
              onReorderItem: (int oldIndex, int newIndex) {
                setState(() {
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

/// 清洗规则的编辑表单（bottom sheet）。
///
/// 以前是 dialog，而且**匹配文字为空时静默 return null** —— 用户点了
/// 「保存规则」，对话框关掉，什么也没发生。现在就地报错、不关表单。
class _RegexRuleSheet extends StatefulWidget {
  const _RegexRuleSheet({this.existing});

  final RegexRule? existing;

  @override
  State<_RegexRuleSheet> createState() => _RegexRuleSheetState();
}

class _RegexRuleSheetState extends State<_RegexRuleSheet> {
  late final TextEditingController _patternCtrl;
  late final TextEditingController _replacementCtrl;

  /// 「要匹配的文字」的就地校验文案；为 null 时不显示错误。
  String? _patternError;

  @override
  void initState() {
    super.initState();
    _patternCtrl = TextEditingController(text: widget.existing?.pattern ?? '');
    _replacementCtrl =
        TextEditingController(text: widget.existing?.replacement ?? '');
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _replacementCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String pattern = _patternCtrl.text.trim();
    if (pattern.isEmpty) {
      setState(() => _patternError = '请填写要匹配的文字');
      return;
    }
    Navigator.of(context).pop(
      RegexRule(
        id: widget.existing?.id ?? newId(),
        pattern: pattern,
        replacement: _replacementCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      // 键盘避让：sheet 跟着输入法一起抬起，不遮住正在编辑的字段。
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FitText(
                widget.existing == null ? '新增清洗规则' : '编辑清洗规则',
                style: theme.textTheme.titleLarge,
              ),
              AppSpacing.hLg,
              TextField(
                controller: _patternCtrl,
                autofocus: true,
                onChanged: (_) {
                  if (_patternError != null) {
                    setState(() => _patternError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: '要匹配的文字',
                  hintText: r'例如：\*[^*]+\* 或 (喵|喵呜)',
                  helperText: '用「模式」描述想找的文字，方括号和竖线表示可选',
                  border: const OutlineInputBorder(),
                  errorText: _patternError,
                ),
              ),
              AppSpacing.hMd,
              TextField(
                controller: _replacementCtrl,
                decoration: const InputDecoration(
                  labelText: '替换为',
                  hintText: '留空表示直接删除匹配内容',
                  border: OutlineInputBorder(),
                ),
              ),
              AppSpacing.hMd,
              Align(
                alignment: Alignment.centerLeft,
                child: FitText(
                  '规则按从上到下的顺序生效，写错的规则会被自动跳过。',
                  style: AppTextStyles.caption(theme).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              AppSpacing.hXl,
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const FitText('取消'),
                    ),
                  ),
                  AppSpacing.wMd,
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const FitText('保存规则'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
