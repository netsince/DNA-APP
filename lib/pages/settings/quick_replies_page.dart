import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';

import '../../models/quick_reply.dart';
import '../../state/app_controller.dart';
import '../../utils/id_utils.dart';
import 'package:dna/widgets/app_empty_state.dart';
import 'package:dna/widgets/fit_text.dart';
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
    return showModalBottomSheet<QuickReply>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
      body: ListView(
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
/// 以前是 AlertDialog：宽度写死 360，而且**先关对话框再校验** —— 发送内容
/// 为空时对话框已经关了，用户只看到一条 snackbar，刚敲的字全丢。现在表单在
/// sheet 里就地校验（地字段 errorText），不通过就不关，输入原样保留。
class _QuickReplySheet extends StatefulWidget {
  const _QuickReplySheet({this.existing});

  final QuickReply? existing;

  @override
  State<_QuickReplySheet> createState() => _QuickReplySheetState();
}

class _QuickReplySheetState extends State<_QuickReplySheet> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _messageCtrl;
  late final TextEditingController _groupCtrl;

  /// 发送内容的就地校验文案；为 null 时不显示错误。
  String? _messageError;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.existing?.label ?? '');
    _messageCtrl = TextEditingController(text: widget.existing?.message ?? '');
    _groupCtrl = TextEditingController(text: widget.existing?.group ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _messageCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String message = _messageCtrl.text.trim();
    if (message.isEmpty) {
      setState(() => _messageError = '发送内容不能为空。');
      return;
    }
    final String label = _labelCtrl.text.trim();
    final String group = _groupCtrl.text.trim();
    Navigator.of(context).pop(
      QuickReply(
        id: widget.existing?.id ?? newId(),
        label: label.isEmpty ? message : label,
        message: message,
        group: group.isEmpty ? null : group,
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
                widget.existing == null ? '新增快速回复' : '编辑快速回复',
                style: theme.textTheme.titleLarge,
              ),
              AppSpacing.hLg,
              TextField(
                controller: _labelCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '按钮显示文字',
                  hintText: '例如：打个招呼、投喂点心',
                  border: OutlineInputBorder(),
                ),
              ),
              AppSpacing.hMd,
              TextField(
                controller: _messageCtrl,
                maxLines: 4,
                minLines: 2,
                onChanged: (_) {
                  if (_messageError != null) {
                    setState(() => _messageError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: '实际发送内容',
                  hintText: '支持宏：{{char}} {{user}} {{random 选项A|选项B}} {{newline}}',
                  border: const OutlineInputBorder(),
                  errorText: _messageError,
                ),
              ),
              AppSpacing.hMd,
              TextField(
                controller: _groupCtrl,
                decoration: const InputDecoration(
                  labelText: '分组标签（选填）',
                  hintText: '用于归类展示，留空表示通用',
                  border: OutlineInputBorder(),
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
                      child: const FitText('保存'),
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
