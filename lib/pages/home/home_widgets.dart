import 'package:flutter/material.dart';

import '../../widgets/state_views.dart';

import '../../models/conversation.dart';
import '../../models/ta.dart';
import '../../models/world.dart';
import '../../services/image_storage.dart';
import '../../state/app_controller.dart';
import '../../theme/tokens.dart';
import '../../utils/error_display.dart';
import '../../widgets/app_container.dart';
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
          // 空态统一走共享组件（审计 3.5「空态三套实现」）。
          return AppEmptyState(
            icon: showArchived
                ? Icons.archive_outlined
                : Icons.chat_bubble_outline,
            title: showArchived ? '还没有归档会话。' : '还没有会话。',
            description: showArchived ? null : '点右上角「＋」或下面的按钮新建一个。',
            actionLabel: showArchived ? null : '新建会话',
            actionIcon: showArchived ? null : Icons.add,
            onAction: showArchived ? null : onCreateConversation,
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          buildDefaultDragHandles: false,
          itemCount: visible.length,
          // onReorderItem 的 newIndex 已按"移除之后"算好，这里不再手动 -1。
          onReorderItem: (int oldIndex, int newIndex) async {
            if (oldIndex < 0 || oldIndex >= visible.length) {
              return;
            }
            final List<Conversation> reordered = <Conversation>[...visible];
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
    // 本列表的数据源是 [AppController.activeConversations] ——**只含单聊**，
    // 群聊在「群聊」栏目里由 group_home_page 渲染。这里曾经写着一整套
    // GroupAvatar 分支，永远走不到，还会让「点进来会显示群」看上去像是坏了。
    final String title = conversation.note.isNotEmpty
        ? conversation.note
        : (ta?.name.isNotEmpty == true ? ta!.name : '未命名会话');
    final String subtitle = world == null
        ? 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'}'
        : 'TA：${ta?.name.isNotEmpty == true ? ta!.name : '未命名TA'} · 世界：${world.name}';

    final Widget leading;
    if (ta != null) {
      final ImageProvider? provider =
          ImageStorage.instance.providerFor(ta, 'square');
      if (provider != null) {
        leading = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            image: ResizeImage.resizeIfNeeded(88, 88, provider),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        );
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

    // OpenContainer 不吃 cardTheme 的外边距:手动补偿原 Card 的底边距。
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppContainer<bool>(
        closedBuilder: (BuildContext context, VoidCallback open) => ListTile(
        leading: leading,
        title: FitText(title),
        subtitle: FitText(subtitle),
        onTap: open,
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
                } else if (value == 'duplicate') {
                  try {
                    await controller.duplicateConversation(conversation.id);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: FitText('复制会话失败：${describeError(e)}'),
                        ),
                      );
                    }
                  }
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[Icon(Icons.unarchive_outlined), AppSpacing.wMd, FitText('恢复')],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[Icon(Icons.delete_outline), AppSpacing.wMd, FitText('删除')],
                      ),
                    ),
                  ];
                }
                return <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: Row(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[Icon(conversation.pinned
                          ? Icons.push_pin_outlined
                          : Icons.push_pin), AppSpacing.wMd, FitText(conversation.pinned ? '取消置顶' : '置顶')],
),
                  ),
                  const PopupMenuItem<String>(
                    value: 'duplicate',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[Icon(Icons.copy_outlined), AppSpacing.wMd, FitText('复制会话')],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[Icon(Icons.edit_outlined), AppSpacing.wMd, FitText('更改信息')],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'archive',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[Icon(Icons.archive_outlined), AppSpacing.wMd, FitText('归档')],
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
      ),
      openBuilder: (BuildContext context, VoidCallback close) => ChatPage(
        controller: controller,
          conversationId: conversation.id,
        ),
      ),
    );
  }
}
