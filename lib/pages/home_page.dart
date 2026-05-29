import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../services/auth_service.dart';
import '../state/app_controller.dart';
import '../utils/ui_feedback.dart';
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
  bool _archiveAuthPassed = false;

  Future<void> _toggleArchived() async {
    final bool willShowArchived = !_showArchived;
    
    // 如果要显示归档且需要验证
    if (willShowArchived && widget.controller.settings.requireAuthForArchive) {
      if (!_archiveAuthPassed) {
        final bool authenticated = await AuthService.authenticateForArchive();
        if (!authenticated) {
          if (mounted) {
            showSnack(context, '验证失败，无法查看归档');
          }
          return;
        }
        _archiveAuthPassed = true;
      }
    }
    
    setState(() => _showArchived = willShowArchived);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当离开归档页面时重置验证状态
    if (!_showArchived) {
      _archiveAuthPassed = false;
    }
  }

  void _createConversation() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ConversationCreatePage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? '归档' : '消息'),
        actions: <Widget>[
          IconButton(
            tooltip: _showArchived ? '查看消息' : '查看归档',
            onPressed: _toggleArchived,
            icon: Icon(_showArchived ? Icons.chat_bubble_outline : Icons.archive_outlined),
          ),
          IconButton(
            tooltip: '新建会话',
            onPressed: _createConversation,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      drawer: AppDrawer(controller: widget.controller, current: AppSection.home),
      body: _ConversationListBody(
        controller: widget.controller,
        showArchived: _showArchived,
        onCreateConversation: _createConversation,
      ),
    );
  }
}

class _ConversationListBody extends StatelessWidget {
  const _ConversationListBody({
    required this.controller,
    required this.showArchived,
    required this.onCreateConversation,
  });

  final AppController controller;
  final bool showArchived;
  final VoidCallback onCreateConversation;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final List<Conversation> conversations = controller.conversations;
        final List<Conversation> visible = conversations
            .where((Conversation c) => c.archived == showArchived)
            .toList();

        if (visible.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  showArchived ? '还没有归档会话。' : '还没有会话，点击右上角 + 新建。',
                ),
                const SizedBox(height: 12),
                if (!showArchived)
                  FilledButton.icon(
                    onPressed: onCreateConversation,
                    icon: const Icon(Icons.add),
                    label: const Text('新建会话'),
                  ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
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
            final int targetIndex = newIndex.clamp(0, reordered.length);
            reordered.insert(targetIndex, moved);
            await controller.reorderConversationSubset(
              reordered.map((Conversation c) => c.id).toList(),
            );
          },
          itemBuilder: (BuildContext context, int index) {
            final Conversation conversation = visible[index];
            return _ConversationItem(
              key: ValueKey<String>(conversation.id),
              controller: controller,
              conversation: conversation,
            );
          },
        );
      },
    );
  }
}

class _ConversationItem extends StatelessWidget {
  const _ConversationItem({
    super.key,
    required this.controller,
    required this.conversation,
  });

  final AppController controller;
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final TA? ta = controller.getTaById(conversation.taId);
    final World? world = controller.getWorldById(conversation.worldId);
    final String title = conversation.note.isNotEmpty
        ? conversation.note
        : (ta?.name.isNotEmpty == true ? ta!.name : '未命名会话');
    final String subtitle = world == null
        ? 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'}'
        : 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'} · 世界：${world.name}';

    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ReorderableDragStartListener(
              index: conversation.archived ? -1 : 0,
              child: const Icon(Icons.drag_handle),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (String value) async {
                if (value == 'archive') {
                  await controller.setConversationArchived(
                    id: conversation.id,
                    archived: true,
                  );
                } else if (value == 'unarchive') {
                  await controller.setConversationArchived(
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
                controller: controller,
                conversationId: conversation.id,
              ),
            ),
          );
        },
      ),
    );
  }
}
