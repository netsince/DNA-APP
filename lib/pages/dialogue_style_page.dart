// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/dialogue_style.dart';
import '../models/ta.dart';
import '../state/app_controller.dart';
import '../widgets/adaptive_text_field.dart';
import 'package:dna/widgets/fit_text.dart';

/// 角色对话风格（Few-shot 示例）配置页。
class DialogueStylePage extends StatefulWidget {
  const DialogueStylePage({super.key, required this.controller, required this.ta});

  final AppController controller;
  final TA ta;

  @override
  State<DialogueStylePage> createState() => _DialogueStylePageState();
}

class _DialogueStylePageState extends State<DialogueStylePage> {
  late List<DialogueTurn> _turns;

  @override
  void initState() {
    super.initState();
    _turns = List<DialogueTurn>.from(widget.ta.dialogueStyle);
    if (_turns.isEmpty) {
      _turns = <DialogueTurn>[const DialogueTurn(user: '', assistant: '')];
    }
  }

  void _addTurn() {
    setState(() => _turns = <DialogueTurn>[..._turns, const DialogueTurn(user: '', assistant: '')]);
  }

  void _removeTurn(int index) {
    if (_turns.length <= 1) {
      return;
    }
    setState(() {
      _turns = <DialogueTurn>[
        ..._turns.take(index),
        ..._turns.skip(index + 1),
      ];
    });
  }

  Future<void> _save() async {
    final TA updated = widget.ta.copyWith(dialogueStyle: List<DialogueTurn>.from(_turns));
    await widget.controller.upsertTa(updated);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const FitText('对话风格（语气范例）'),
        actions: <Widget>[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: '保存',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _turns.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        FitText(
                          '对话风格说明',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FitText(
                      '每轮示例包含【你的提问】与【TA的回答】。AI 会模仿示例中的用词、口吻、动作描写与语气习惯。',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          final int turnIndex = index - 1;
          final DialogueTurn turn = _turns[turnIndex];

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      FitText(
                        '范例第 ${turnIndex + 1} 轮',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (_turns.length > 1)
                        IconButton(
                          onPressed: () => _removeTurn(turnIndex),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: '删除此轮',
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 1. 用户发言（我一句）
                  TextFormField(
                    initialValue: turn.user,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: '你的发言（输入）',
                      hintText: '例如：今天天气真好，一起去散步吗？',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                    onChanged: (String value) {
                      _turns[turnIndex] = _turns[turnIndex].copyWith(user: value);
                    },
                  ),
                  const SizedBox(height: 10),

                  // 2. 角色回答（你一句）
                  AdaptiveTextField(
                    key: ValueKey<String>('assist_${turnIndex}_${turn.assistant.hashCode}'),
                    controller: TextEditingController(text: turn.assistant),
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: 'TA 的回答 / 语气范例（输出）',
                      hintText: '例如：哼，既然你都邀请了，本小姐就勉为其难陪你走走吧。',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.smart_toy_outlined, size: 20),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                    onChanged: (String value) {
                      _turns[turnIndex] = _turns[turnIndex].copyWith(assistant: value);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTurn,
        icon: const Icon(Icons.add),
        label: const FitText('添加对话范例'),
      ),
    );
  }
}
