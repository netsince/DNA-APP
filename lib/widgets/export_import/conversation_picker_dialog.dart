import 'package:flutter/material.dart';

import '../../models/conversation.dart';

/// 选择要导出的对话。
Future<List<String>?> showConversationPickerDialog({
  required BuildContext context,
  required List<Conversation> conversations,
  required Map<String, String> nameById,
}) async {
  final selected = <String>{};
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('选择要导出的对话'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: StatefulBuilder(
            builder: (bc, setSB) => ListView(
              children: conversations.map((c) {
                final n = nameById[c.id] ?? '未命名';
                final sel = selected.contains(c.id);
                return CheckboxListTile(
                  value: sel,
                  title: Text(n),
                  onChanged: (v) {
                    setSB(() {
                      if (v == true) {
                        selected.add(c.id);
                      } else {
                        selected.remove(c.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected.toList()),
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
}
