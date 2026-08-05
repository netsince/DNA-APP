import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/ta.dart';
import '../../models/world.dart';
import '../../state/app_controller.dart';
import '../../widgets/group_avatar.dart';
import '../chat_page.dart';
import '../conversation_edit_page.dart';
import '../delete_confirm_page.dart';
import '../delete_preview_builders.dart';
import 'package:dna/widgets/fit_text.dart';

class ConversationListBody extends StatelessWidget {
  const ConversationListBody({
    super.key,
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
        // 置顶会话排在前面，其余保持原有相对顺序。
        visible.sort((Conversation a, Conversation b) {
          if (a.pinned != b.pinned) {
            return a.pinned ? -1 : 1;
          }
          return 0;
        });

        if (visible.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FitText(
                  showArchived ? '还没有归档会话。' : '还没有会话，点击右上角 + 新建。',
                ),
                const SizedBox(height: 12),
                if (!showArchived)
                  FilledButton.icon(
                    onPressed: onCreateConversation,
                    icon: const Icon(Icons.add),
                    label: const FitText('新建会话'),
                  ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          buildDefaultDragHandles: false,
          itemCount: visible.length,
          onReorder: (int oldIndex, int newIndex) async { // ignore: deprecated_member_use
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

    final Widget leading;
    if (conversation.isGroup) {
      final List<TA> members = conversation.memberTaIds
          .map(controller.getTaById)
          .whereType<TA>()
          .toList();
      leading = GroupAvatar(tas: members, size: 44);
    } else if (ta != null) {
      final String? square = ta.images['square'];
      if (square != null && square.isNotEmpty) {
        final File file = File(square);
        if (file.existsSync()) {
          leading = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              cacheWidth: 88,
              cacheHeight: 88,
            ),
          );
        } else {
          leading = CircleAvatar(
            radius: 22,
            child: FitText(ta.name.isNotEmpty ? ta.name[0] : '?'),
          );
        }
      } else {
        leading = CircleAvatar(
          radius: 22,
          child: FitText(ta.name.isNotEmpty ? ta.name[0] : '?'),
        );
      }
    } else {
      leading = const CircleAvatar(
        radius: 22,
        child: Icon(Icons.person_outline),
      );
    }

    return Card(
      child: ListTile(
        leading: leading,
        title: FitText(title),
        subtitle: FitText(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (conversation.pinned) ...<Widget>[
              Icon(Icons.push_pin,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
            ],
            ReorderableDragStartListener(
              index: conversation.archived ? -1 : 0,
              child: const Icon(Icons.drag_handle),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (String value) async {
                if (value == 'edit') {
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => ConversationEditPage(
                        controller: controller,
                        conversation: conversation,
                      ),
                    ),
                  );
                } else if (value == 'pin') {
                  await controller.setConversationPinned(
                    id: conversation.id,
                    pinned: !conversation.pinned,
                  );
                } else if (value == 'archive') {
                  await controller.setConversationArchived(
                    id: conversation.id,
                    archived: true,
                  );
                } else if (value == 'unarchive') {
                  await controller.setConversationArchived(
                    id: conversation.id,
                    archived: false,
                  );
                } else if (value == 'delete') {
                  if (!context.mounted) return;
                  final TA? ta = controller.getTaById(conversation.taId);
                  final String taName = ta?.name ?? '';
                  final List<String> validNames =
                      taName.isNotEmpty ? <String>[taName] : <String>[];
                  final String promptHint = taName.isNotEmpty
                      ? '请完整输入你对话的角色名「$taName」以确认删除'
                      : '该对话关联角色名缺失，请输入任意文字以确认删除';
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (BuildContext context) => DeleteConfirmPage(
                        controller: controller,
                        title: '删除对话',
                        entityName: taName.isNotEmpty ? taName : '该对话',
                        validNames: validNames,
                        promptHint: promptHint,
                        contentBuilder: (BuildContext ctx) =>
                            buildConversationPreviewSections(
                                ctx, controller, conversation),
                        onDelete: () =>
                            controller.deleteConversationWithBackup(
                                conversation.id),
                        requireName: controller.settings.requireNameToDelete,
                      ),
                    ),
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
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: ListTile(
                      leading: Icon(conversation.pinned
                          ? Icons.push_pin_outlined
                          : Icons.push_pin),
                      title: FitText(conversation.pinned ? '取消置顶' : '置顶'),
                    ),
                  ),
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
