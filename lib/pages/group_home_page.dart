import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/group_avatar.dart';
import 'chat_page.dart';
import 'group_create_page.dart';

class GroupHomePage extends StatefulWidget {
  const GroupHomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GroupHomePage> createState() => _GroupHomePageState();
}

class _GroupHomePageState extends State<GroupHomePage> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final List<Conversation> groups = widget.controller.groupConversations
            .where((Conversation c) => c.isGroup)
            .toList();
        final List<Conversation> visible =
            groups.where((Conversation c) => c.archived == _showArchived).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(_showArchived ? '群聊归档' : '群聊'),
            actions: <Widget>[
              IconButton(
                tooltip: _showArchived ? '查看群聊' : '查看归档',
                onPressed: () => setState(() => _showArchived = !_showArchived),
                icon: Icon(_showArchived ? Icons.forum_outlined : Icons.archive_outlined),
              ),
              IconButton(
                tooltip: '新建群聊',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          GroupCreatePage(controller: widget.controller),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          drawer: AppDrawer(controller: widget.controller, current: AppSection.groupChats),
          body: visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(_showArchived ? '还没有归档群聊。' : '还没有群聊，点击右上角 + 新建。'),
                      const SizedBox(height: 12),
                      if (!_showArchived)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    GroupCreatePage(controller: widget.controller),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('新建群聊'),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Conversation group = visible[index];
                    final List<TA> members = group.memberTaIds
                        .map(widget.controller.getTaById)
                        .whereType<TA>()
                        .toList();
                    final World? world = widget.controller.getWorldById(group.worldId);
                    final String title = group.groupName.trim().isNotEmpty
                        ? group.groupName.trim()
                        : '未命名群聊';
                    final String subtitle = world == null
                        ? '成员：${members.length}'
                        : '成员：${members.length} · 世界：${world.name}';
                    return Card(
                      key: ValueKey<String>(group.id),
                      child: ListTile(
                        leading: GroupAvatar(tas: members, size: 44),
                        title: Text(title),
                        subtitle: Text(subtitle),
                        trailing: PopupMenuButton<String>(
                          tooltip: '更多操作',
                          onSelected: (String value) async {
                            if (value == 'archive') {
                              await widget.controller.setGroupConversationArchived(
                                id: group.id,
                                archived: true,
                              );
                            } else if (value == 'unarchive') {
                              await widget.controller.setGroupConversationArchived(
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
                                controller: widget.controller,
                                conversationId: group.id,
                                isGroup: true,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
