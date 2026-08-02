import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_drawer.dart';
import '../widgets/group_avatar.dart';
import 'chat_page.dart';
import 'delete_confirm_page.dart';
import 'delete_preview_builders.dart';
import 'group_create_page.dart';
import 'group_edit_page.dart';
import 'package:dna/widgets/fit_text.dart';

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
    return AppScaffold(
      controller: widget.controller,
      current: AppSection.groupChats,
      appBar: AppBar(
        title: FitText(_showArchived ? '群聊归档' : '群聊'),
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
      body: _GroupListBody(
        controller: widget.controller,
        showArchived: _showArchived,
        onCreateGroup: _createGroup,
      ),
      bottomNavigationBar: widget.controller.settings.showBottomNav
          ? AppBottomNav(
              controller: widget.controller, current: AppSection.groupChats)
          : null,
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
                FitText(showArchived ? '还没有归档群聊。' : '还没有群聊，点击右上角 + 新建。'),
                const SizedBox(height: 12),
                if (!showArchived)
                  FilledButton.icon(
                    onPressed: onCreateGroup,
                    icon: const Icon(Icons.add),
                    label: const FitText('新建群聊'),
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
        title: FitText(title),
        subtitle: FitText(subtitle),
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
            } else if (value == 'delete') {
              if (!context.mounted) return;
              final List<String> memberNames = group.memberTaIds
                  .map(controller.getTaById)
                  .whereType<TA>()
                  .map((TA t) => t.name)
                  .where((String n) => n.isNotEmpty)
                  .toList();
              final String hint = memberNames.isNotEmpty
                  ? '请完整输入任意一名成员名（${memberNames.join(' / ')}）以确认删除'
                  : '该群聊成员名缺失，请输入任意文字以确认删除';
              await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (BuildContext context) => DeleteConfirmPage(
                    controller: controller,
                    title: '删除群聊',
                    entityName: group.groupName.trim().isNotEmpty
                        ? group.groupName.trim()
                        : '该群聊',
                    validNames: memberNames,
                    promptHint: hint,
                    contentBuilder: (BuildContext ctx) =>
                        buildConversationPreviewSections(
                            ctx, controller, group),
                    onDelete: () =>
                        controller.deleteConversationWithBackup(group.id),
                    requireName: controller.settings.requireNameToDelete,
                  ),
                ),
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
                    title: FitText('恢复'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: FitText('删除'),
                  ),
                ),
              ];
            }
            return <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: FitText('更改信息'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.archive_outlined),
                  title: FitText('归档'),
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
