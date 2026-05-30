import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../utils/ui_feedback.dart';

class ConversationEditPage extends StatefulWidget {
  const ConversationEditPage({
    super.key,
    required this.controller,
    required this.conversation,
  });

  final AppController controller;
  final Conversation conversation;

  @override
  State<ConversationEditPage> createState() => _ConversationEditPageState();
}

class _ConversationEditPageState extends State<ConversationEditPage> {
  late String? _selectedTaId;
  late String? _selectedWorldId;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _selectedTaId = widget.conversation.taId;
    _selectedWorldId = widget.conversation.worldId;
    _noteController = TextEditingController(text: widget.conversation.note);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedTaId == null || _selectedTaId!.isEmpty) {
      showSnack(context, '请选择TA。');
      return;
    }
    final Conversation updated = widget.conversation.copyWith(
      taId: _selectedTaId!,
      worldId: (_selectedWorldId == null || _selectedWorldId!.isEmpty)
          ? null
          : _selectedWorldId,
      note: _noteController.text.trim(),
    );
    await widget.controller.upsertConversation(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<TA> tas = widget.controller.activeTas;
    final List<World> worlds = widget.controller.activeWorlds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('更改信息'),
        actions: <Widget>[
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: '保存',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('选择TA（必选）', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (tas.isEmpty)
                    const Text('暂无TA，请先在"我家"创建TA。')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTaId,
                      decoration: const InputDecoration(labelText: 'TA'),
                      items: tas
                          .map(
                            (TA ta) => DropdownMenuItem<String>(
                              value: ta.id,
                              child: Text(ta.name.isEmpty ? '未命名TA' : ta.name),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) =>
                          setState(() => _selectedTaId = value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('选择世界背景（可选）', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (worlds.isEmpty)
                    const Text('暂无世界背景，可在"世界"页面创建。')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedWorldId ?? '',
                      decoration: const InputDecoration(labelText: '世界背景'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('不选择'),
                        ),
                        ...worlds.map(
                          (World world) => DropdownMenuItem<String>(
                            value: world.id,
                            child: Text(
                              world.name.isEmpty ? '未命名世界' : world.name,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (String? value) {
                        setState(() {
                          _selectedWorldId =
                              (value == null || value.isEmpty) ? null : value;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('备注', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: '可选备注'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.check),
        label: const Text('保存'),
      ),
    );
  }
}
