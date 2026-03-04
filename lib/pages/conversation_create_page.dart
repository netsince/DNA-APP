import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../utils/ui_feedback.dart';

class ConversationCreatePage extends StatefulWidget {
  const ConversationCreatePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConversationCreatePage> createState() => _ConversationCreatePageState();
}

class _ConversationCreatePageState extends State<ConversationCreatePage> {
  String? _selectedTaId;
  String? _selectedWorldId;
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _generateId() {
    return newId();
  }

  Future<void> _create() async {
    if (_selectedTaId == null) {
      showSnack(context, '请先选择TA。');
      return;
    }

    String id = _generateId();
    final Set<String> existing = widget.controller.conversations.map((Conversation c) => c.id).toSet();
    while (existing.contains(id)) {
      id = _generateId();
    }

    final Conversation conversation = Conversation(
      id: id,
      taId: _selectedTaId!,
      worldId: _selectedWorldId,
      note: _noteController.text.trim(),
      messages: const <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberTaIds: <String>[_selectedTaId!],
      activeTaId: _selectedTaId!,
    );

    await widget.controller.upsertConversation(conversation);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<TA> tas = widget.controller.tas;
    final List<World> worlds = widget.controller.worlds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新建会话'),
        actions: <Widget>[
          IconButton(
            onPressed: _create,
            icon: const Icon(Icons.check),
            tooltip: '创建',
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
                    const Text('暂无TA，请先在“我家”创建TA。')
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
                      onChanged: (String? value) => setState(() => _selectedTaId = value),
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
                    const Text('暂无世界背景，可在“世界”页面创建。')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedWorldId,
                      decoration: const InputDecoration(labelText: '世界背景'),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(value: '', child: Text('不选择')),
                        ...worlds.map(
                          (World world) => DropdownMenuItem<String>(
                            value: world.id,
                            child: Text(world.name.isEmpty ? '未命名世界' : world.name),
                          ),
                        ),
                      ],
                      onChanged: (String? value) {
                        setState(() {
                          _selectedWorldId = (value == null || value.isEmpty) ? null : value;
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
        onPressed: _create,
        icon: const Icon(Icons.check),
        label: const Text('创建会话'),
      ),
    );
  }
}
