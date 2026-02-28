import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/role.dart';
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
  String? _selectedRoleId;
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
    if (_selectedRoleId == null) {
      showSnack(context, '请先选择角色。');
      return;
    }

    String id = _generateId();
    final Set<String> existing = widget.controller.conversations.map((Conversation c) => c.id).toSet();
    while (existing.contains(id)) {
      id = _generateId();
    }

    final Conversation conversation = Conversation(
      id: id,
      roleId: _selectedRoleId!,
      worldId: _selectedWorldId,
      note: _noteController.text.trim(),
      messages: const <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: false,
      groupName: '',
      groupPrompt: '',
      memberRoleIds: <String>[_selectedRoleId!],
      activeRoleId: _selectedRoleId!,
    );

    await widget.controller.upsertConversation(conversation);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<Role> roles = widget.controller.roles;
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
                  Text('选择角色（必选）', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (roles.isEmpty)
                    const Text('暂无角色，请先在“我家”创建角色。')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRoleId,
                      decoration: const InputDecoration(labelText: '角色'),
                      items: roles
                          .map(
                            (Role role) => DropdownMenuItem<String>(
                              value: role.id,
                              child: Text(role.name.isEmpty ? '未命名角色' : role.name),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) => setState(() => _selectedRoleId = value),
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
                  Text('选择世界观（可选）', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (worlds.isEmpty)
                    const Text('暂无世界观，可在“世界”页面创建。')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedWorldId,
                      decoration: const InputDecoration(labelText: '世界观'),
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
