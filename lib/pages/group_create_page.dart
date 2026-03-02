import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../utils/id_utils.dart';
import '../utils/ui_feedback.dart';
import '../widgets/group_avatar.dart';

class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  String? _selectedWorldId;
  final Set<String> _selectedTaIds = <String>{};

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  String _generateId() {
    return newId();
  }

  Future<void> _create() async {
    if (_selectedTaIds.isEmpty) {
      showSnack(context, '请选择至少一个TA。');
      return;
    }
    final List<String> memberIds = _selectedTaIds.toList();
    String id = _generateId();
    final Set<String> existing =
        widget.controller.groupConversations.map((Conversation c) => c.id).toSet();
    while (existing.contains(id)) {
      id = _generateId();
    }
    final Conversation conversation = Conversation(
      id: id,
      taId: memberIds.first,
      worldId: _selectedWorldId,
      note: '',
      messages: const <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: true,
      groupName: _nameController.text.trim(),
      groupPrompt: _promptController.text.trim(),
      memberTaIds: memberIds,
      activeTaId: memberIds.first,
    );
    await widget.controller.upsertGroupConversation(conversation);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<TA> tas = widget.controller.tas;
    final List<World> worlds = widget.controller.worlds;
    final List<TA> selectedTas = tas.where((TA t) => _selectedTaIds.contains(t.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('新建群聊'),
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
                  Text('群名称', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '群名称（可选）'),
                  ),
                  const SizedBox(height: 16),
                  Text('群设定', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _promptController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '群设定文本',
                      hintText: '用于群聊的系统设定，和世界观并存。',
                    ),
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
                  Text('世界观（可选）', style: Theme.of(context).textTheme.titleLarge),
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
                  Text('群成员（至少选一位）', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (tas.isEmpty)
                    const Text('暂无TA，请先在“我家”创建TA。')
                  else
                    Column(
                      children: tas.map((TA ta) {
                        final bool checked = _selectedTaIds.contains(ta.id);
                        return CheckboxListTile(
                          value: checked,
                          title: Text(ta.name.isEmpty ? '未命名TA' : ta.name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedTaIds.add(ta.id);
                              } else {
                                _selectedTaIds.remove(ta.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  if (selectedTas.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        const Text('群头像预览：'),
                        const SizedBox(width: 8),
                        GroupAvatar(tas: selectedTas, size: 56),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.check),
        label: const Text('创建群聊'),
      ),
    );
  }
}
