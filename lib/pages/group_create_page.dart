import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/role.dart';
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
  final Set<String> _selectedRoleIds = <String>{};

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
    if (_selectedRoleIds.isEmpty) {
      showSnack(context, '请选择至少一个角色。');
      return;
    }
    final List<String> memberIds = _selectedRoleIds.toList();
    String id = _generateId();
    final Set<String> existing =
        widget.controller.groupConversations.map((Conversation c) => c.id).toSet();
    while (existing.contains(id)) {
      id = _generateId();
    }
    final Conversation conversation = Conversation(
      id: id,
      roleId: memberIds.first,
      worldId: _selectedWorldId,
      note: '',
      messages: const <ConversationMessage>[],
      backgroundMode: 'none',
      summaries: const <ConversationSummary>[],
      archived: false,
      isGroup: true,
      groupName: _nameController.text.trim(),
      groupPrompt: _promptController.text.trim(),
      memberRoleIds: memberIds,
      activeRoleId: memberIds.first,
    );
    await widget.controller.upsertGroupConversation(conversation);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<Role> roles = widget.controller.roles;
    final List<World> worlds = widget.controller.worlds;
    final List<Role> selectedRoles = roles.where((Role r) => _selectedRoleIds.contains(r.id)).toList();

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
                  if (roles.isEmpty)
                    const Text('暂无角色，请先在“我家”创建角色。')
                  else
                    Column(
                      children: roles.map((Role role) {
                        final bool checked = _selectedRoleIds.contains(role.id);
                        return CheckboxListTile(
                          value: checked,
                          title: Text(role.name.isEmpty ? '未命名角色' : role.name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedRoleIds.add(role.id);
                              } else {
                                _selectedRoleIds.remove(role.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  if (selectedRoles.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        const Text('群头像预览：'),
                        const SizedBox(width: 8),
                        GroupAvatar(roles: selectedRoles, size: 56),
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
