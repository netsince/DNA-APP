import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/group_avatar.dart';
import 'chat_page.dart';
import 'group_create_page.dart';
import 'group_edit_page.dart';

class GroupHomePage extends StatefulWidget {
  const GroupHomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GroupHomePage> createState() => _GroupHomePageState();
}

class _GroupHomePageState extends State<GroupHomePage> {
  bool _showArchived = false;

  void _toggleArchived() {
    setState(() => _showArchived = !_showArchived);
  }

  void _createGroup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            GroupCreatePage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? '群聊归档' : '群聊'),
        actions: <Widget>[
          IconButton(
            tooltip: _showArchived ? '查看群聊' : '查看归档',
            onPressed: _toggleArchived,
            icon: Icon(_showArchived ? Icons.forum_outlined : Icons.archive_outlined),
          ),
          IconButton(
            tooltip: '新建群聊',
            onPressed: _createGroup,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      drawer: AppDrawer(controller: widget.controller, current: AppSection.groupChats),
      body: _GroupListBody(
        controller: widget.controller,
        showArchived: _showArchived,
        onCreateGroup: _createGroup,
      ),
    );
  }
}

class _GroupListBody extends StatelessWidget {
  const _GroupListBody({
    required this.controller,
    required this.showArchived,
    required this.onCreateGroup,
  });

  final AppController controller;
  final bool showArchived;
  final VoidCallback onCreateGroup;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final List<Conversation> visible = controller.groupConversations
            .where((Conversation c) => c.archived == showArchived)
            .toList();

        if (visible.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(showArchived ? '还没有归档群聊。' : '还没有群聊，点击右上角 + 新建。'),
                const SizedBox(height: 12),
                if (!showArchived)
                  FilledButton.icon(
                    onPressed: onCreateGroup,
                    icon: const Icon(Icons.add),
                    label: const Text('新建群聊'),
                  ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: visible.length,
          itemBuilder: (BuildContext context, int index) {
            final Conversation group = visible[index];
            return _GroupItem(
              key: ValueKey<String>(group.id),
              controller: controller,
              group: group,
            );
          },
        );
      },
    );
  }
}

class _GroupItem extends StatelessWidget {
  const _GroupItem({
    super.key,
    required this.controller,
    required this.group,
  });

  final AppController controller;
  final Conversation group;

  @override
  Widget build(BuildContext context) {
    final List<TA> members = group.memberTaIds
        .map(controller.getTaById)
        .whereType<TA>()
        .toList();
    final World? world = controller.getWorldById(group.worldId);
    final String title = group.groupName.trim().isNotEmpty
        ? group.groupName.trim()
        : '未命名群聊';
    final String subtitle = world == null
        ? '成员：${members.length}'
        : '成员：${members.length} · 世界：${world.name}';

    return Card(
      child: ListTile(
        leading: GroupAvatar(tas: members, size: 44),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: PopupMenuButton<String>(
          tooltip: '更多操作',
          onSelected: (String value) async {
            if (value == 'edit') {
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => GroupEditPage(
                    controller: controller,
                    group: group,
                  ),
                ),
              );
            } else if (value == 'archive') {
              await controller.setGroupConversationArchived(
                id: group.id,
                archived: true,
              );
            } else if (value == 'unarchive') {
              await controller.setGroupConversationArchived(
                id: group.id,
                archived: false,
              );
            }
          },
          itemBuilder: (BuildContext context) {
            if (group.archived) {
              return <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'unarchive',
                  child: ListTile(
                    leading: Icon(Icons.unarchive_outlined),
                    title: Text('恢复'),
                  ),
                ),
              ];
            }
            return <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('更改信息'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.archive_outlined),
                  title: Text('归档'),
                ),
              ),
            ];
          },
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => ChatPage(
                controller: controller,
                conversationId: group.id,
                isGroup: true,
              ),
            ),
          );
        },
      ),
    );
  }
}
