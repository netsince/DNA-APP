import 'package:material_ui/material_ui.dart';

import '../../widgets/state_views.dart';

import '../models/conversation.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/action_table.dart';
import '../utils/error_display.dart';
import '../widgets/app_container.dart';
import '../widgets/app_icon_flight.dart';
import '../widgets/app_responsive_wrap.dart';
import '../widgets/app_section.dart';
import '../widgets/group_avatar.dart';
import 'chat_page.dart';
import 'delete_confirm_page.dart';
import 'delete_preview_builders.dart';
import 'group_create_page.dart';
import 'group_edit_page.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/utils/ui_feedback.dart';

/// 群聊栏目装配。
SectionPageData groupHomeSection(AppController controller) {
  final ValueNotifier<bool> showArchived = ValueNotifier<bool>(false);

  void createGroup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            GroupCreatePage(controller: controller),
      ),
    );
  }

  return SectionPageData(
    section: AppSection.groupChats,
    showArchived: showArchived,
    // 卡片列表:宽屏并排多列,内容列相应放宽。
    contentMaxWidth: AppSize.pageMaxWidth,
    appBar: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) => AppBar(
        title: FitText(archived ? '群聊归档' : '群聊'),
        actions: <Widget>[
          IconButton(
            tooltip: archived ? '查看群聊' : '查看归档',
            onPressed: () => showArchived.value = !archived,
            icon: Icon(
              archived ? Icons.forum_outlined : Icons.archive_outlined,
            ),
          ),
          // 新建群聊页:从图标位置放大,返回时缩回。
          AppBarIconAction<bool>(
            tooltip: '新建群聊',
            icon: Icons.add,
            pageBuilder: (BuildContext context) =>
                GroupCreatePage(controller: controller),
          ),
        ],
      ),
    ),
    body: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) =>
          GroupListBody(
            controller: controller,
            showArchived: archived,
            onCreateGroup: () => createGroup(context),
          ),
    ),
  );
}

class GroupListBody extends StatelessWidget {
  const GroupListBody({
    super.key,
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
      listenable: Listenable.merge(<Listenable>[controller.dataChanges, controller.settingsChanges]),
      builder: (BuildContext context, Widget? _) {
        final List<Conversation> visible = controller.groupConversations
            .where((Conversation c) => c.archived == showArchived)
            .toList();
        // 置顶群聊排在前面，其余保持原有相对顺序。
        visible.sort((Conversation a, Conversation b) {
          if (a.pinned != b.pinned) {
            return a.pinned ? -1 : 1;
          }
          return 0;
        });

        if (visible.isEmpty) {
          return AppEmptyState(
            icon: showArchived ? Icons.archive_outlined : Icons.forum_outlined,
            title: showArchived ? '还没有归档群聊。' : '还没有群聊。',
            description: showArchived ? null : '点右上角「＋」或下面的按钮新建一个。',
            actionLabel: showArchived ? null : '新建群聊',
            actionIcon: showArchived ? null : Icons.add,
            onAction: showArchived ? null : onCreateGroup,
          );
        }

        // 卡片列表:宽窗口并排多列(窄窗口自动回落单列)。
        return AppResponsiveWrap(
          padding: const EdgeInsets.all(16),
          itemCount: visible.length,
          minItemWidth: 340,
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
  const _GroupItem({super.key, required this.controller, required this.group});

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

    // OpenContainer 不吃 cardTheme 外边距:手动补偿原 Card 底边距。
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppContainer<bool>(
        closedBuilder: (BuildContext context, VoidCallback open) => ListTile(
          leading: GroupAvatar(tas: members, size: 44),
          title: FitText(title),
          subtitle: FitText(subtitle),
          onTap: open,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (group.pinned) ...<Widget>[
                Icon(
                  Icons.push_pin,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
              ],
              rowActionMenu(
                tooltip: '更多操作',
                child: const Icon(Icons.more_vert),
                // 归档态 / 未归档态共用这一张动作表：可见项由 visible 区分。
                // 菜单项沿用本页原来的非紧凑 ListTile（图标 24、零内边距）。
                itemStyle: RowActionItemStyle.listTileRegular,
                iconSize: 24,
                actions: <RowAction>[
                  RowAction(
                    id: 'pin',
                    label: group.pinned ? '取消置顶' : '置顶',
                    icon: group.pinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin,
                    visible: !group.archived,
                    onSelected: () async {
                      await controller.setGroupConversationPinned(
                        id: group.id,
                        pinned: !group.pinned,
                      );
                    },
                  ),
                  RowAction(
                    id: 'duplicate',
                    label: '复制群聊',
                    icon: Icons.copy_outlined,
                    visible: !group.archived,
                    onSelected: () async {
                      try {
                        await controller.duplicateConversation(group.id);
                      } catch (e) {
                        if (context.mounted) {
                          showSnack(context, '复制群聊失败：${describeError(e)}');
                        }
                      }
                    },
                  ),
                  RowAction(
                    id: 'edit',
                    label: '更改信息',
                    icon: Icons.edit_outlined,
                    visible: !group.archived,
                    onSelected: () async {
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              GroupEditPage(controller: controller, group: group),
                        ),
                      );
                    },
                  ),
                  RowAction(
                    id: 'archive',
                    label: '归档',
                    icon: Icons.archive_outlined,
                    visible: !group.archived,
                    onSelected: () async {
                      await controller.setGroupConversationArchived(
                        id: group.id,
                        archived: true,
                      );
                    },
                  ),
                  RowAction(
                    id: 'unarchive',
                    label: '恢复',
                    icon: Icons.unarchive_outlined,
                    visible: group.archived,
                    // 原来「恢复」与「删除」之间的那条分隔线。
                    dividerAfter: true,
                    onSelected: () async {
                      await controller.setGroupConversationArchived(
                        id: group.id,
                        archived: false,
                      );
                    },
                  ),
                  RowAction(
                    id: 'delete',
                    label: '删除',
                    icon: Icons.delete_outline,
                    visible: group.archived,
                    onSelected: () async {
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
                                  ctx,
                                  controller,
                                  group,
                                ),
                            onDelete: () =>
                                controller.deleteConversationWithBackup(group.id),
                            requireName: controller.settings.requireNameToDelete,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        openBuilder: (BuildContext context, VoidCallback close) => ChatPage(
          controller: controller,
          conversationId: group.id,
          isGroup: true,
        ),
      ),
    );
  }
}
