import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_drawer.dart';
import 'chat_page.dart';
import 'conversation_create_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final List<Conversation> conversations = widget.controller.conversations;
        final List<Conversation> visible = conversations
            .where((Conversation c) => c.archived == _showArchived)
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(_showArchived ? '归档' : '消息'),
            actions: <Widget>[
              IconButton(
                tooltip: _showArchived ? '查看消息' : '查看归档',
                onPressed: () {
                  setState(() => _showArchived = !_showArchived);
                },
                icon: Icon(_showArchived ? Icons.chat_bubble_outline : Icons.archive_outlined),
              ),
              IconButton(
                tooltip: '新建会话',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          ConversationCreatePage(controller: widget.controller),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          drawer: AppDrawer(controller: widget.controller, current: AppSection.home),
          body: visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _showArchived ? '还没有归档会话。' : '还没有会话，点击右上角 + 新建。',
                      ),
                      const SizedBox(height: 12),
                      if (!_showArchived)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    ConversationCreatePage(controller: widget.controller),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('新建会话'),
                        ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(16),
                  buildDefaultDragHandles: false,
                  itemCount: visible.length,
                  onReorder: (int oldIndex, int newIndex) async {
                    if (oldIndex < 0 || oldIndex >= visible.length) {
                      return;
                    }
                    final List<Conversation> reordered = <Conversation>[...visible];
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final Conversation moved = reordered.removeAt(oldIndex);
                    final int targetIndex = newIndex.clamp(0, reordered.length) as int;
                    reordered.insert(targetIndex, moved);
                    await widget.controller.reorderConversationSubset(
                      reordered.map((Conversation c) => c.id).toList(),
                    );
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final Conversation conversation = visible[index];
                    final TA? ta = widget.controller.getTaById(conversation.taId);
                    final World? world = widget.controller.getWorldById(conversation.worldId);
                    final String title = conversation.note.isNotEmpty
                        ? conversation.note
                        : (ta?.name.isNotEmpty == true ? ta!.name : '未命名会话');
                    final String subtitle = world == null
                        ? 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'}'
                        : 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'} · 世界：${world.name}';
                    return Card(
                      key: ValueKey<String>(conversation.id),
                      child: ListTile(
                        title: Text(title),
                        subtitle: Text(subtitle),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              tooltip: '更多操作',
                              onSelected: (String value) async {
                                if (value == 'archive') {
                                  await widget.controller.setConversationArchived(
                                    id: conversation.id,
                                    archived: true,
                                  );
                                } else if (value == 'unarchive') {
                                  await widget.controller.setConversationArchived(
                                    id: conversation.id,
                                    archived: false,
                                  );
                                }
                              },
                              itemBuilder: (BuildContext context) {
                                if (conversation.archived) {
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
                              child: const Icon(Icons.more_vert),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => ChatPage(
                                controller: widget.controller,
                                conversationId: conversation.id,
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
