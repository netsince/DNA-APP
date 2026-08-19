// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../models/quick_reply.dart';
import '../../state/app_controller.dart';
import '../../utils/id_utils.dart';
import 'package:dna/widgets/fit_text.dart';

/// 快速回复管理页：新增 / 编辑 / 删除聊天输入栏上方的一键发送按钮。
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
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ts = theme.textTheme;

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: <Widget>[
          // ===== 顶部引导卡片 =====
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
                      Icon(Icons.bolt, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      FitText('一键快速回复', style: ts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FitText(
                    '在聊天输入栏上方展示快捷操作按钮，点击即发送指定句式。\n'
                    '支持动态占位变量：\n'
                    '• {{char}}：自动替换为当前角色名\n'
                    '• {{user}}：自动替换为我的身份昵称\n'
                    '• {{random 选项A|选项B}}：随机挑选一个词条发送\n'
                    '• {{newline}}：换行',
                    style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (_items.isEmpty)
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
                  Icon(Icons.flash_on_outlined, size: 40, color: cs.outline),
                  const SizedBox(height: 10),
                  const FitText('暂无快速回复短语'),
                  const SizedBox(height: 6),
                  FitText('点击右上角【+】或下方按钮添加常用快捷发送语句', style: ts.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const FitText('新增快速回复'),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _items.map((QuickReply qr) {
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.bolt, color: cs.onPrimaryContainer, size: 18),
                    ),
                    title: Row(
                      children: <Widget>[
                        FitText(qr.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                        if ((qr.group ?? '').isNotEmpty) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FitText(
                              qr.group!,
                              style: TextStyle(fontSize: 11, color: cs.onSecondaryContainer),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: FitText(
                        qr.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
