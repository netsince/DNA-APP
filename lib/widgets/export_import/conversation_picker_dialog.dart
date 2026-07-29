import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import 'package:dna/widgets/fit_text.dart';

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
        title: const FitText('选择要导出的对话'),
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
                  title: FitText(n),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const FitText('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected.toList()),
            child: const FitText('确定'),
          ),
        ],
      );
    },
  );
}
