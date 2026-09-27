// ignore_for_file: deprecated_member_use
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
    final QuickReply? created = await _editDialog();
    if (created == null) return;
    setState(() {
      _items = <QuickReply>[..._items, created];
    });
    await _save();
  }

  Future<void> _edit(QuickReply item) async {
    final QuickReply? updated = await _editDialog(item);
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

  Future<QuickReply?> _editDialog([QuickReply? existing]) async {
    final TextEditingController labelCtrl =
        TextEditingController(text: existing?.label ?? '');
    final TextEditingController messageCtrl =
        TextEditingController(text: existing?.message ?? '');
    final TextEditingController groupCtrl =
        TextEditingController(text: existing?.group ?? '');

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: FitText(existing == null ? '新增快速回复' : '编辑快速回复'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: labelCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '按钮显示文字',
                    hintText: '例如：打个招呼、投喂点心',
                    border: OutlineInputBorder(),
                  ),
                ),
                AppSpacing.hMd,
                TextField(
                  controller: messageCtrl,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: '实际发送内容',
                    hintText: '支持宏：{{char}} {{user}} {{random 选项A|选项B}} {{newline}}',
                    border: OutlineInputBorder(),
                  ),
                ),
                AppSpacing.hMd,
                TextField(
                  controller: groupCtrl,
                  decoration: const InputDecoration(
                    labelText: '分组标签（选填）',
                    hintText: '用于归类展示，留空表示通用',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('保存'),
          ),
        ],
      ),
    );

    if (ok != true) return null;
    final String label = labelCtrl.text.trim();
    final String message = messageCtrl.text.trim();
    if (message.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: FitText('发送内容不能为空。')),
        );
      }
      return null;
    }
    return QuickReply(
      id: existing?.id ?? newId(),
      label: label.isEmpty ? message : label,
      message: message,
      group: groupCtrl.text.trim().isEmpty ? null : groupCtrl.text.trim(),
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
