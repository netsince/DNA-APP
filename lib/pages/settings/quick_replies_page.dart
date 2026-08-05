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
    if (created == null) {
      return;
    }
    setState(() {
      _items = <QuickReply>[..._items, created];
    });
    await _save();
  }

  Future<void> _edit(QuickReply item) async {
    final QuickReply? updated = await _editDialog(item);
    if (updated == null) {
      return;
    }
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

  /// 新增 / 编辑对话框，返回新的 QuickReply（取消返回 null）。
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: '按钮文字'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageCtrl,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: '发送内容',
                  hintText: '支持宏：{{char}} {{user}} {{random:a|b}} {{newline}}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: groupCtrl,
                decoration: const InputDecoration(
                  labelText: '分组（可选）',
                  hintText: '留空表示不分组',
                ),
              ),
            ],
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
    if (ok != true) {
      return null;
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const FitText('快速回复'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const FitText(
            '聊天输入栏上方会显示这些一键发送按钮，点击即可发送预设内容，支持宏替换。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: FitText('还没有快速回复，点击右下角添加')),
            )
          else
            Column(
              children: _items
                  .map(
                    (QuickReply qr) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bolt),
                      title: FitText(qr.label),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if ((qr.group ?? '').isNotEmpty)
                            FitText('分组：${qr.group}', style: const TextStyle(fontSize: 12)),
                          FitText(
                            qr.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      onTap: () => _edit(qr),
                      trailing: IconButton(
                        onPressed: () => _delete(qr),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除',
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const FitText('新增'),
      ),
    );
  }
}
