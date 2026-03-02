import 'package:flutter/material.dart';

import '../models/dialogue_style.dart';
import '../models/ta.dart';
import '../state/app_controller.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话风格'),
        actions: <Widget>[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _turns.length,
        itemBuilder: (BuildContext context, int index) {
          final DialogueTurn turn = _turns[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('轮次 ${index + 1}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: turn.user,
                    decoration: const InputDecoration(labelText: '我一句'),
                    onChanged: (String value) {
                      _turns[index] = turn.copyWith(user: value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: turn.assistant,
                    decoration: const InputDecoration(labelText: '你一句'),
                    onChanged: (String value) {
                      _turns[index] = turn.copyWith(assistant: value);
                    },
                  ),
                  if (_turns.length > 1) ...<Widget>[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _removeTurn(index),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除轮次'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTurn,
        icon: const Icon(Icons.add),
        label: const Text('添加轮次'),
      ),
    );
  }
}
