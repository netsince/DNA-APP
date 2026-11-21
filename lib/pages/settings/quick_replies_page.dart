import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../models/quick_reply.dart';
import '../../state/app_controller.dart';
import '../../utils/id_utils.dart';
import 'package:dna/widgets/app_empty_state.dart';
import 'package:dna/widgets/app_content_frame.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/form_draft.dart';
import 'package:dna/widgets/form_fields.dart';
import 'package:dna/widgets/form_sheet.dart';
import 'package:dna/widgets/setting_section.dart';

/// 快速回复管理页：新增 / 编辑 / 删除聊天输入栏上方的一键发送按钮。
///
/// **本次改造**(见 `SETTINGS_AUDIT.md`):
/// * 顶部引导卡片改写为 `SettingSection`(带图标分组标题 + 短说明),
///   `subtitle` 不再承载 52 字长文案 —— 用法说明移到 `SettingHint`;
/// * 顶部引导卡片的 52 字长说明 → 短句 + 逐条宏变量说明;
/// * 首页空状态改用 `AppEmptyState` 组件(消除手写
///   `Container > Column > Icon + Text` 样板);
/// * 列表项卡片样板改用令牌(圆角/间距/透明度),语义不变。
///
/// **不套 `SettingSection` 的部分**:下方是「快速回复短语」列表(可增删改、
/// 可拖动排序的**条目集合**),不是设置项堆叠,按规矩 1 的豁免说明保留列表结构。
class QuickRepliesPage extends StatefulWidget {
  const QuickRepliesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<QuickRepliesPage> createState() => _QuickRepliesPageState();
}

class _QuickRepliesPageState extends State<QuickRepliesPage> {
  late List<QuickReply> _items;

  @override
  void initState() {
    super.initState();
    _items = List<QuickReply>.from(widget.controller.settings.quickReplies);
  }

  Future<void> _save() async {
    await widget.controller.saveQuickReplies(_items);
  }

  Future<void> _add() async {
    final QuickReply? created = await _editSheet();
    if (created == null) return;
    setState(() {
      _items = <QuickReply>[..._items, created];
    });
    await _save();
  }

  Future<void> _edit(QuickReply item) async {
    final QuickReply? updated = await _editSheet(item);
    if (updated == null) return;
    setState(() {
      _items = _items
          .map((QuickReply q) => q.id == item.id ? updated : q)
          .toList();
    });
    await _save();
  }

  Future<void> _delete(QuickReply item) async {
    setState(() {
      _items = _items.where((QuickReply q) => q.id != item.id).toList();
    });
    await _save();
  }

  /// 打开编辑表单。
  ///
  /// 容器是 bottom sheet 而不是 dialog：这是「填写一张小表单」，不是
  /// 需要立刻拍板的决定（审计 3.2）。sheet 还带来了富余的横向宽度，
  /// 原来的 dialog 宽度写死 360，长宏示例在窄窗口里会被挤成三行。
  Future<QuickReply?> _editSheet([QuickReply? existing]) {
    return FormSheet.show<QuickReply>(
      context: context,
      builder: (BuildContext sheetContext) =>
          _QuickReplySheet(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const FitText('快速回复管理'),
        actions: <Widget>[
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.add),
            tooltip: '新增回复',
          ),
        ],
      ),
      body: AppContentFrame(
        maxWidth: AppSize.pageMaxWidth,
        child: ListView(
          padding: AppInsets.page,
          children: <Widget>[
            // ===== 用法说明(不再用手写卡片样板) =====
            SettingSection(
              icon: Icons.bolt_outlined,
              title: '什么是一键快速回复',
              description: '点一下按钮，就把整句话发出去。',
              children: <Widget>[
                SettingHint(
                  '{{char}} 当前角色名 · {{user}} 你的昵称 · '
                  '{{random 甲|乙}} 随机二选一 · {{newline}} 换行',
                  icon: Icons.help_outline,
                ),
              ],
            ),

            // ===== 短语列表（条目集合，非设置项堆叠）=====
            if (_items.isEmpty)
              AppEmptyState(
                icon: Icons.flash_on_outlined,
                title: '还没有快速回复',
                description: '添加常用短句，聊天时点一下就发送。',
                actionLabel: '新增快速回复',
                actionIcon: Icons.add,
                onAction: _add,
              )
            else
              Column(
                children: _items.map((QuickReply qr) {
                  return Card(
                    elevation: AppElevation.flat,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    shape: AppBorder.secondaryShape(cs),
                    child: ListTile(
                      contentPadding: AppInsets.group,
                      leading: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer
                              .withValues(alpha: AppAlpha.half),
                          borderRadius: AppRadius.xsAll,
                        ),
                        child: Icon(
                          Icons.bolt,
                          color: cs.onPrimaryContainer,
                          size: AppSize.iconInline,
                        ),
                      ),
                      title: Row(
                        children: <Widget>[
                          FitText(
                            qr.label,
                            style: const TextStyle(
                              fontWeight: AppWeight.medium,
                            ),
                          ),
                          if ((qr.group ?? '').isNotEmpty) ...<Widget>[
                            AppSpacing.wSm,
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: AppRadius.xsAll,
                              ),
                              child: FitText(
                                qr.group!,
                                style: TextStyle(
                                  fontSize: AppFontSize.tiny,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: FitText(
                          qr.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption(theme)
                              .copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: '编辑',
                            onPressed: () => _edit(qr),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: '删除',
                            onPressed: () => _delete(qr),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
      floatingActionButton: _items.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const FitText('新增快速回复'),
            )
          : null,
    );
  }
}

/// 快速回复的编辑表单（bottom sheet）。
///
/// 骨架（标题 / 字段间距 / 键盘避让 / 取消·保存）来自共享 [FormSheet]，
/// 字段值走 [FormDraft]、校验用 [FormDraft.validateRequired] 落到字段
/// errorText 上：不通过就不关表单，输入原样保留。
///
/// 以前是 AlertDialog：宽度写死 360，而且**先关对话框再校验** —— 发送内容
/// 为空时对话框已经关了，用户只看到一条 snackbar，刚敲的字全丢。
class _QuickReplySheet extends StatefulWidget {
  const _QuickReplySheet({this.existing});

  final QuickReply? existing;

  @override
  State<_QuickReplySheet> createState() => _QuickReplySheetState();
}

class _QuickReplySheetState extends State<_QuickReplySheet> {
  late final FormDraft _draft;

  @override
  void initState() {
    super.initState();
    final QuickReply? existing = widget.existing;
    _draft = FormDraft(
      textFields: const <String>['label', 'message', 'group'],
    );
    _draft.controller('label').text = existing?.label ?? '';
    _draft.controller('message').text = existing?.message ?? '';
    _draft.controller('group').text = existing?.group ?? '';
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _submit() {
    // 必填校验落在「实际发送内容」这个字段上（不是 snackbar）。
    if (!_draft.validateRequired(<(String, String)>[
      ('message', '发送内容不能为空。'),
    ])) {
      setState(() {});
      return;
    }
    final String message = _draft.text('message');
    final String label = _draft.text('label');
    final String group = _draft.text('group');
    Navigator.of(context).pop(
      QuickReply(
        id: widget.existing?.id ?? newId(),
        // 没填按钮文字就用发送内容兜底（和聊天栏里看到的那个按钮一致）。
        label: label.isEmpty ? message : label,
        message: message,
        group: group.isEmpty ? null : group,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: widget.existing == null ? '新增快速回复' : '编辑快速回复',
      onSubmit: _submit,
      children: <Widget>[
        FormTextField(
          draft: _draft,
          id: 'label',
          label: '按钮显示文字',
          hint: '例如：打个招呼、投喂点心',
          // 打开 sheet 就能直接输入。
          autofocus: true,
        ),
        FormTextField(
          draft: _draft,
          id: 'message',
          label: '实际发送内容',
          hint: '支持宏：{{char}} {{user}} {{random 选项A|选项B}} {{newline}}',
          minLines: 2,
          maxLines: 4,
          // 一输入就清掉必填错误（FormTextField 只清草稿，重建归页面）。
          onChanged: (_) => setState(() {}),
        ),
        FormTextField(
          draft: _draft,
          id: 'group',
          label: '分组标签（选填）',
          hint: '用于归类展示，留空表示通用',
        ),
      ],
    );
  }
}
